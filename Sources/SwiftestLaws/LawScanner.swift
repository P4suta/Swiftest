import Foundation
import SwiftParser
import SwiftParserDiagnostics
import SwiftSyntax
import SwiftestModel
import SwiftestPlatform

public enum LawScanner {
    public static func scan(root: String) throws(LawScannerError) -> LawReport {
        try scan(root: root, inputClosure: .unrestricted)
    }

    public static func scan(
        root: String,
        declaredInputs: [String]
    ) throws(LawScannerError) -> LawReport {
        try scan(root: root, inputClosure: .declared(declaredInputs))
    }

    private enum InputClosure {
        case unrestricted
        case declared([String])
    }

    private static func scan(
        root: String,
        inputClosure: InputClosure
    ) throws(LawScannerError) -> LawReport {
        let normalizedRoot = URL(fileURLWithPath: root).standardizedFileURL.path
        if normalizedRoot.isEmpty {
            throw .invalidRoot(root)
        }
        let inventory = sourceFiles(root: normalizedRoot)
        let paths = inventory.paths
        var violations = inventory.violations
        switch inputClosure {
        case .unrestricted:
            break
        case .declared(let inputs):
            let discovered = Set(paths.map { relativePath($0, root: normalizedRoot) })
            let declared = Set(inputs)
            if declared.count != inputs.count {
                violations.append(violation(
                    .unclassifiedSource,
                    file: "Plugins/SwiftestLawsPlugin",
                    subject: "duplicate-plugin-input"
                ))
            }
            for relative in discovered.symmetricDifference(declared).sorted() {
                violations.append(violation(
                    .unclassifiedSource,
                    file: relative,
                    subject: "plugin-input-closure"
                ))
            }
        }
        var importsByPath: [String: Set<String>] = [:]
        for path in paths {
            let relative = relativePath(path, root: normalizedRoot)
            if relative.hasSuffix(".md") || relative.hasSuffix(".markdown") {
                violations.append(violation(.handwrittenDocumentation, file: relative, subject: "markdown"))
                continue
            }
            if !shouldScan(relative) {
                violations.append(violation(.unclassifiedSource, file: relative, subject: "file"))
                continue
            }
            let data: Data
            do {
                data = try FileSystemBoundary.read(path: path)
            } catch {
                violations.append(violation(.unreadableSource, file: relative, subject: "read"))
                continue
            }
            guard let source = String(data: data, encoding: .utf8) else {
                violations.append(violation(.unreadableSource, file: relative, subject: "utf8"))
                continue
            }
            violations.append(contentsOf: scanFile(relativePath: relative, source: source, data: data))
            if relative.hasSuffix(".swift") {
                importsByPath[relative] = importedModules(source)
            }
        }
        violations.append(contentsOf: validateModuleGraph(importsByPath: importsByPath, root: normalizedRoot))
        let count: EvidenceCount
        do {
            count = try .nonnegative(paths.count)
        } catch let error {
            throw .count(error)
        }
        let sorted = violations.sorted {
            if $0.location.file != $1.location.file {
                return $0.location.file < $1.location.file
            }
            if $0.location.line != $1.location.line {
                return $0.location.line < $1.location.line
            }
            if $0.location.column != $1.location.column {
                return $0.location.column < $1.location.column
            }
            if $0.law.rawValue != $1.law.rawValue {
                return $0.law.rawValue < $1.law.rawValue
            }
            return $0.subject < $1.subject
        }
        return LawReport(checkedFiles: count, violations: sorted)
    }

    public static func scanSwiftSource(
        _ source: String,
        path: String
    ) -> [LawViolation] {
        let tree = Parser.parse(source: source)
        var violations: [LawViolation] = []
        let parseDiagnostics = ParseDiagnosticsGenerator.diagnostics(for: tree)
        if !parseDiagnostics.isEmpty {
            violations.append(violation(.unreadableSource, file: path, subject: "parse"))
        }
        let tokens = Array(tree.tokens(viewMode: .sourceAccurate))
        for token in tokens {
            var leadingOffset = token.position.utf8Offset
            for trivia in token.leadingTrivia {
                if let text = commentText(trivia),
                    !isAllowedComment(text: text, path: path, source: source, offset: leadingOffset) {
                    violations.append(violation(
                        .forbiddenComment,
                        file: path,
                        source: source,
                        offset: leadingOffset,
                        subject: commentKind(text)
                    ))
                }
                leadingOffset += trivia.sourceLength.utf8Length
            }
            var trailingOffset = token.endPositionBeforeTrailingTrivia.utf8Offset
            for trivia in token.trailingTrivia {
                if let text = commentText(trivia) {
                    violations.append(violation(
                        .forbiddenComment,
                        file: path,
                        source: source,
                        offset: trailingOffset,
                        subject: commentKind(text)
                    ))
                }
                trailingOffset += trivia.sourceLength.utf8Length
            }
        }
        let records = tokens.compactMap { token -> TokenRecord? in
            if isLiteralMaterial(token.tokenKind) {
                return nil
            }
            return TokenRecord(
                text: token.text,
                offset: token.positionAfterSkippingLeadingTrivia.utf8Offset,
                isFileScope: isFileScope(token),
                isTypeStaticVar: isTypeStaticVar(token),
                isForceUnwrap: token.tokenKind == .exclamationMark
            )
        }
        violations.append(contentsOf: tokenViolations(records, source: source, path: path))
        violations.append(contentsOf: macroViolations(tokens, path: path))
        return violations
    }

    private static func scanFile(relativePath: String, source: String, data: Data) -> [LawViolation] {
        if relativePath.hasSuffix(".swift") {
            let syntaxViolations = scanSwiftSource(source, path: relativePath)
            if relativePath == "Package.swift" {
                return syntaxViolations + PackageManifestGraph.violations(in: source)
            }
            return syntaxViolations
        }
        let flavor: SourceFlavor
        if relativePath.hasSuffix(".lean") {
            flavor = .lean
        } else if relativePath.hasSuffix(".json") {
            flavor = .json
        } else if relativePath.hasSuffix(".yml")
            || relativePath.hasSuffix(".yaml")
            || relativePath.hasSuffix(".toml")
            || relativePath == ".gitignore"
            || relativePath.hasPrefix("Scripts/")
            || relativePath.hasPrefix(".githooks/") {
            flavor = .hash
        } else {
            flavor = .plain
        }
        var violations: [LawViolation] = []
        if flavor == .json && !OtherSourceLexer.validatesJSON(data) {
            violations.append(violation(.unreadableSource, file: relativePath, subject: "json"))
        }
        for comment in OtherSourceLexer.comments(in: source, flavor: flavor) {
            if isAllowedOtherComment(comment, path: relativePath) {
                continue
            }
            violations.append(violation(
                .forbiddenComment,
                file: relativePath,
                source: source,
                offset: comment.offset,
                subject: "comment"
            ))
        }
        return violations
    }

    private static func tokenViolations(
        _ tokens: [TokenRecord],
        source: String,
        path: String
    ) -> [LawViolation] {
        var violations: [LawViolation] = []
        let platformBoundary = path.hasPrefix("Sources/SwiftestPlatform/")
        let abiBoundary = path == "Sources/" + AuditedBoundary.platformABI.rawValue
        let testingBoundary = path == "Sources/" + AuditedBoundary.testingStableABI.rawValue
        let pluginInputBoundary = path == "Plugins/SwiftestLawsPlugin/PluginInputInventory.swift"
        let hasClosedDomain = containsSequence(["@", "ClosedDomain"], tokens: tokens)
        for index in tokens.indices {
            let token = tokens[index]
            let previous = index > 0 ? tokens[index - 1].text : ""
            let beforePrevious = index > 1 ? tokens[index - 2].text : ""
            let next = index + 1 < tokens.count ? tokens[index + 1].text : ""
            let nextTwo = index + 2 < tokens.count ? tokens[index + 2].text : ""
            if token.text == "try" && (next == "?" || next == "!") {
                violations.append(at(.prohibitedTry, token: token, source: source, path: path))
            }
            if token.text == "as" && next == "!" {
                violations.append(at(.forceCast, token: token, source: source, path: path))
            }
            if token.isForceUnwrap {
                violations.append(at(.forceUnwrap, token: token, source: source, path: path))
            }
            if token.text == "throw" && next.hasPrefix("\"") {
                violations.append(at(.stringError, token: token, source: source, path: path))
            }
            if token.text == "NSError" {
                violations.append(at(.stringError, token: token, source: source, path: path))
            }
            if token.text == "_" && next == "=" {
                violations.append(at(.ignoredResult, token: token, source: source, path: path))
            }
            if token.text == "??" {
                violations.append(at(.semanticDefault, token: token, source: source, path: path))
            }
            if token.text == "Bool" && (next == "?" || (previous == "<" && next == ">")) {
                violations.append(at(.optionalBoolean, token: token, source: source, path: path))
            }
            if token.text == ":" && next == "Bool" && isPolicyName(previous) {
                violations.append(at(.policyBoolean, token: token, source: source, path: path))
            }
            if hasClosedDomain && token.text == "default" && next == ":" {
                violations.append(at(.defaultClosedDomain, token: token, source: source, path: path))
            }
            if token.text == "static" && next == "let" && nextTwo == "allCases" {
                violations.append(at(.handwrittenCases, token: token, source: source, path: path))
            }
            if token.text == "Process" && !platformBoundary {
                violations.append(at(.rawProcess, token: token, source: source, path: path))
            }
            if token.text == "Task" && next == "." && nextTwo == "detached" && !platformBoundary {
                violations.append(at(.detachedTask, token: token, source: source, path: path))
            }
            if token.text == "var" && (token.isFileScope || token.isTypeStaticVar) {
                violations.append(at(.globalMutableState, token: token, source: source, path: path))
            }
            if token.text == "any" && !testingBoundary && !platformBoundary && previous != "isolated" {
                violations.append(at(.ownedExistential, token: token, source: source, path: path))
            }
            if token.text == "Any" {
                violations.append(at(.anyType, token: token, source: source, path: path))
            }
            if token.text == "Mirror" {
                violations.append(at(.mirror, token: token, source: source, path: path))
            }
            if token.text == "&+" || token.text == "&-" || token.text == "&*" {
                violations.append(at(.uncheckedArithmetic, token: token, source: source, path: path))
            }
            if token.text == "ProcessInfo" && !platformBoundary {
                violations.append(at(.directEnvironment, token: token, source: source, path: path))
            }
            if (token.text == "ContinuousClock" || (token.text == "Date" && nextTwo == "now"))
                && !platformBoundary {
                violations.append(at(.directClock, token: token, source: source, path: path))
            }
            if (token.text == "SystemRandomNumberGenerator"
                || token.text == "UUID"
                || (previous == "." && token.text == "random" && next == "(" && nextTwo == "in"))
                && !platformBoundary {
                violations.append(at(.directRandomness, token: token, source: source, path: path))
            }
            if ((token.text == "FileManager" && !pluginInputBoundary)
                || (token.text == "createDirectory"
                    && next == "("
                    && !(beforePrevious == "FileSystemBoundary" && previous == "."))
                || token.text == "removeItem"
                || token.text == "moveItem"
                || token.text == "copyItem"
                || token.text == "createFile"
                || token.text == "replaceItem"
                || token.text == "setAttributes"
                || (previous == "." && token.text == "write" && next == "(" && nextTwo == "to"))
                && !platformBoundary {
                violations.append(at(.directFileWrite, token: token, source: source, path: path))
            }
            if !abiBoundary && libcFilesystemSymbols.contains(token.text) {
                violations.append(at(.directFileWrite, token: token, source: source, path: path))
            }
            if !abiBoundary && (token.text == "open" || token.text == "link") && next == "("
                && previous != "func" && previous != "case" {
                violations.append(at(.directFileWrite, token: token, source: source, path: path))
            }
            if !abiBoundary && token.text == "write" && next == "("
                && previous != "func" && previous != "case"
                && (previous != "." || beforePrevious == "Darwin" || beforePrevious == "Foundation") {
                violations.append(at(.directFileWrite, token: token, source: source, path: path))
            }
            if !abiBoundary && token.text == "remove" && next == "("
                && previous != "func" && previous != "case"
                && (previous != "." || beforePrevious == "Darwin" || beforePrevious == "Foundation") {
                violations.append(at(.directFileWrite, token: token, source: source, path: path))
            }
            if !abiBoundary && libcProcessSymbols.contains(token.text) {
                violations.append(at(.rawProcess, token: token, source: source, path: path))
            }
            if (token.text.hasPrefix("withUnsafe")
                || token.text.hasPrefix("UnsafePointer")
                || token.text == "unsafeBitCast"
                || token.text == "_silgen_name"
                || (token.text == "unchecked" && previous == "@"))
                && !abiBoundary {
                violations.append(at(.unsafeOutsideBoundary, token: token, source: source, path: path))
            }
        }
        return violations
    }

    private static func macroViolations(_ tokens: [TokenSyntax], path: String) -> [LawViolation] {
        let allowed: [String: [(module: String, type: String)]] = [
            "WorldTest": [("SwiftestMacros", "WorldTestMacro")],
            "WorldUITest": [("SwiftestMacros", "WorldUITestMacro")],
            "Property": [("SwiftestMacros", "PropertyMacro")],
            "StateMachineTest": [("SwiftestMacros", "StateMachineTestMacro")],
            "PerformanceClaim": [("SwiftestMacros", "PerformanceClaimMacro")],
            "TestDouble": [("SwiftestMacros", "TestDoubleMacro")],
            "ClosedDomain": [("SwiftestMacros", "ClosedDomainMacro")],
            "eventually": [("SwiftestMacros", "EventuallyMacro")],
            "invariant": [("SwiftestMacros", "InvariantMacro")],
            "never": [("SwiftestMacros", "NeverMacro")],
        ]
        var violations: [LawViolation] = []
        for index in tokens.indices {
            guard tokens[index].text == "#",
                !isLiteralMaterial(tokens[index].tokenKind),
                index + 1 < tokens.count,
                tokens[index + 1].text == "externalMacro" else {
                continue
            }
            let arguments = Array(tokens.dropFirst(index + 2).prefix(12)).map(\.text)
            let module = macroArgument("module", in: arguments)
            let type = macroArgument("type", in: arguments)
            let declaration = containingMacroName(for: tokens[index])
            let inspected: Bool
            if let declaration, let implementations = allowed[declaration] {
                inspected = implementations.contains { module == $0.module && type == $0.type }
            } else {
                inspected = false
            }
            if path != "Sources/SwiftestTesting/Macros.swift" || !inspected {
                let subject: String
                if let declaration {
                    subject = declaration
                } else {
                    subject = "external-macro"
                }
                violations.append(violation(.uninspectedMacro, file: path, subject: subject))
            }
        }
        return violations
    }

    private static func containingMacroName(for token: TokenSyntax) -> String? {
        var node = Syntax(token)
        while let parent = node.parent {
            if let declaration = parent.as(MacroDeclSyntax.self) {
                return declaration.name.text
            }
            node = parent
        }
        return nil
    }

    private static func macroArgument(_ label: String, in tokens: [String]) -> String? {
        for index in tokens.indices where tokens[index] == label {
            if index + 4 < tokens.count,
                tokens[index + 1] == ":",
                tokens[index + 2] == "\"",
                tokens[index + 4] == "\"" {
                return tokens[index + 3]
            }
        }
        return nil
    }

    private static func validateModuleGraph(
        importsByPath: [String: Set<String>],
        root: String
    ) -> [LawViolation] {
        let declarations = Dictionary(uniqueKeysWithValues: SwiftestModuleGraph.declarations.map { ($0.name, $0) })
        var violations: [LawViolation] = []
        let targetRoots = ["Sources", "Tests", "Plugins"]
        for targetRoot in targetRoots {
            let path = root + "/" + targetRoot
            let kind: FileEntryKind
            do {
                kind = try FileSystemBoundary.entryKind(path: path)
            } catch {
                continue
            }
            if kind != .directory {
                violations.append(violation(.unclassifiedTarget, file: targetRoot, subject: "not-directory"))
                continue
            }
            let entries: [String]
            do {
                entries = try FileSystemBoundary.list(path: path)
            } catch {
                violations.append(violation(.unreadableSource, file: targetRoot, subject: "list"))
                continue
            }
            for entry in entries {
                if declarations[entry] == nil {
                    violations.append(violation(
                        .unclassifiedTarget,
                        file: targetRoot + "/" + entry,
                        subject: entry
                    ))
                }
            }
        }
        for declaration in SwiftestModuleGraph.declarations {
            let directory: String
            switch declaration.role {
            case .test:
                directory = "Tests"
            case .plugin:
                directory = "Plugins"
            case .production, .executable, .macro:
                directory = "Sources"
            }
            let relative = directory + "/" + declaration.name
            let kind: FileEntryKind
            do {
                kind = try FileSystemBoundary.entryKind(path: root + "/" + relative)
            } catch {
                violations.append(violation(.unclassifiedTarget, file: relative, subject: "missing-target"))
                continue
            }
            if kind != .directory {
                violations.append(violation(.unclassifiedTarget, file: relative, subject: "not-directory"))
            }
        }
        for relative in importsByPath.keys.sorted() {
            guard let module = moduleName(relativePath: relative) else {
                continue
            }
            guard let declaration = declarations[module] else {
                continue
            }
            guard let imports = importsByPath[relative] else {
                continue
            }
            for imported in imports.sorted() {
                if SwiftestModuleGraph.permitsSystemImport(
                    imported,
                    declaration: declaration,
                    relativePath: relative
                ) {
                    continue
                }
                if SwiftestModuleGraph.recognizedSystemModules.contains(imported) {
                    violations.append(violation(.reverseDependency, file: relative, subject: imported))
                    continue
                }
                if imported.hasSuffix("Tests") && declaration.role != .test {
                    violations.append(violation(.testSupportImport, file: relative, subject: imported))
                    continue
                }
                if !declaration.dependencies.contains(imported) {
                    violations.append(violation(.reverseDependency, file: relative, subject: imported))
                }
                if module == "SwiftestDecision"
                    && (imported == "SwiftestScore"
                        || imported == "SwiftestPresentation"
                        || imported == "SwiftestUI") {
                    violations.append(violation(.reverseDependency, file: relative, subject: imported))
                }
            }
        }
        let productRoots: Set<String> = ["Swiftest", "SwiftestCLI", "SwiftestLaws", "SwiftestTesting"]
        var reachable = productRoots
        var changed = true
        while changed {
            changed = false
            for module in Array(reachable) {
                guard let declaration = declarations[module] else {
                    continue
                }
                let previousCount = reachable.count
                reachable.formUnion(declaration.dependencies)
                if reachable.count != previousCount {
                    changed = true
                }
            }
        }
        for declaration in SwiftestModuleGraph.declarations
            where declaration.role == .production && !reachable.contains(declaration.name) {
            violations.append(violation(
                .unreachableProduction,
                file: "Sources/" + declaration.name,
                subject: declaration.name
            ))
        }
        return violations
    }

    private static func importedModules(_ source: String) -> Set<String> {
        let tree = Parser.parse(source: source)
        let texts = Array(tree.tokens(viewMode: .sourceAccurate)).compactMap { token in
            isLiteralMaterial(token.tokenKind) ? nil : token.text
        }
        var imports = Set<String>()
        let selectiveKinds: Set<String> = ["typealias", "struct", "class", "enum", "protocol", "func", "var", "let"]
        for index in texts.indices where texts[index] == "import" && index + 1 < texts.count {
            let first = index + 1
            let moduleIndex = selectiveKinds.contains(texts[first]) ? first + 1 : first
            if moduleIndex < texts.count {
                imports.insert(texts[moduleIndex])
            }
        }
        return imports
    }

    private static func sourceFiles(root: String) -> SourceInventory {
        var inventory = SourceInventory()
        walk(path: root, root: root, inventory: &inventory)
        inventory.paths.sort()
        return inventory
    }

    private static func walk(path: String, root: String, inventory: inout SourceInventory) {
        let relative = relativePath(path, root: root)
        let kind: FileEntryKind
        do {
            kind = try FileSystemBoundary.entryKind(path: path)
        } catch {
            inventory.violations.append(violation(.unreadableSource, file: relative, subject: "entry"))
            return
        }
        switch kind {
        case .file:
            inventory.paths.append(path)
        case .directory:
            if ignoredDirectory(relative) {
                return
            }
            if !relative.isEmpty && !relative.contains("/") && !allowedTopLevelDirectories.contains(relative) {
                inventory.violations.append(violation(.unclassifiedSource, file: relative, subject: "directory"))
            }
            let entries: [String]
            do {
                entries = try FileSystemBoundary.list(path: path)
            } catch {
                inventory.violations.append(violation(.unreadableSource, file: relative, subject: "list"))
                return
            }
            for entry in entries {
                walk(path: path + "/" + entry, root: root, inventory: &inventory)
            }
        case .symbolicLink, .other:
            inventory.violations.append(violation(.unreadableSource, file: relative, subject: kind.rawValue))
        }
    }

    private static func shouldScan(_ path: String) -> Bool {
        let components = path.split(separator: "/")
        guard let root = components.first else {
            return false
        }
        if components.count == 1 {
            return allowedRootFiles.contains(path)
        }
        switch root {
        case "Sources", "Tests", "Plugins":
            return components.count >= 3 && path.hasSuffix(".swift")
        case "SwiftestProofs":
            return components.count == 2 && path.hasSuffix(".lean")
        case "Scripts":
            return components.count == 2 && allowedScripts.contains(String(components[1]))
        case ".githooks":
            return path == ".githooks/pre-push"
        case ".github":
            return components.count == 3
                && components[1] == "workflows"
                && (path.hasSuffix(".yml") || path.hasSuffix(".yaml"))
        case "Fixtures":
            guard components.count >= 4 && components[1] == "CompileFail" else {
                return false
            }
            if components.count == 4 {
                return components[3] == "Package.swift"
            }
            return components.count == 6
                && components[3] == "Sources"
                && components[4] == components[2]
                && path.hasSuffix(".swift")
        default:
            return false
        }
    }

    private static let allowedRootFiles: Set<String> = [
        ".gitignore", "LICENSE", "Package.swift", "SwiftestProofs.lean", "lake-manifest.json",
        "lakefile.toml", "lean-toolchain",
    ]

    private static let allowedScripts: Set<String> = [
        "compile-fail", "dogfood", "formal-check", "mutate-laws", "platform-check", "quality",
    ]

    private static func ignoredDirectory(_ relative: String) -> Bool {
        relative == ".git"
            || relative == ".build"
            || relative == ".swiftpm"
            || relative == ".lake"
            || relative == ".local-signing"
            || relative == "DerivedData"
            || relative == "dist"
    }

    private static let allowedTopLevelDirectories: Set<String> = [
        ".githooks", ".github", "Fixtures", "Plugins", "Scripts", "Sources", "SwiftestProofs", "Tests",
    ]

    private static func moduleName(relativePath: String) -> String? {
        let components = relativePath.split(separator: "/").map(String.init)
        if components.count < 2 {
            return nil
        }
        if components[0] == "Sources" || components[0] == "Tests" || components[0] == "Plugins" {
            return components[1]
        }
        return nil
    }

    private static func relativePath(_ path: String, root: String) -> String {
        if path == root {
            return ""
        }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        if path.hasPrefix(prefix) {
            return String(path.dropFirst(prefix.count))
        }
        return path
    }

    private static func commentText(_ trivia: TriviaPiece) -> String? {
        switch trivia {
        case .lineComment(let text),
            .blockComment(let text),
            .docLineComment(let text),
            .docBlockComment(let text):
            text
        default:
            nil
        }
    }

    private static func isAllowedComment(text: String, path: String, source: String, offset: Int) -> Bool {
        let location = locationIn(source: source, offset: offset)
        if path.hasSuffix("Package.swift")
            && source.hasPrefix(text)
            && text == "// swift-tools-version: 6.2" {
            return true
        }
        if text == "// SPDX-License-Identifier: Apache-2.0"
            || text == "// SPDX-License-Identifier: MIT" {
            if location.line == 1 && source.hasPrefix(text) {
                return true
            }
            return path.hasSuffix("Package.swift")
                && location.line == 2
                && source.hasPrefix("// swift-tools-version: 6.2\n" + text)
        }
        return false
    }

    private static func isAllowedOtherComment(_ comment: LexedComment, path: String) -> Bool {
        path.hasPrefix("Scripts/") && comment.offset == 0 && comment.text == "#!/bin/sh"
            || path.hasPrefix(".githooks/") && comment.offset == 0 && comment.text == "#!/bin/sh"
    }

    private static func commentKind(_ text: String) -> String {
        if text.hasPrefix("///") || text.hasPrefix("/**") {
            return "documentation-comment"
        }
        return "comment"
    }

    private static func isLiteralMaterial(_ kind: TokenKind) -> Bool {
        switch kind {
        case .stringQuote,
            .multilineStringQuote,
            .stringSegment,
            .rawStringPoundDelimiter,
            .regexLiteralPattern,
            .regexPoundDelimiter,
            .regexSlash:
            true
        default:
            false
        }
    }

    private static func isPolicyName(_ text: String) -> Bool {
        let names: Set<String> = [
            "allow",
            "enabled",
            "include",
            "isEnabled",
            "policy",
            "skip",
            "strict",
            "update",
            "useCache",
        ]
        return names.contains(text)
    }

    private static let libcFilesystemSymbols: Set<String> = [
        "openat", "creat", "fopen", "freopen", "fdopen", "fwrite", "pwrite",
        "writev", "pwritev", "unlink", "unlinkat", "rename", "renameat", "rmdir",
        "mkdir", "mkdirat", "symlink", "symlinkat", "linkat", "truncate",
        "ftruncate", "chmod", "chown", "fchmod", "fchown", "mknod", "mkfifo",
        "mkstemp", "mkdtemp", "copyfile", "fcopyfile", "clonefile", "exchangedata",
        "setxattr", "fsetxattr", "removexattr", "fremovexattr",
    ]

    private static let libcProcessSymbols: Set<String> = [
        "system", "popen", "fork", "vfork", "posix_spawn", "posix_spawnp",
        "execve", "execv", "execvp", "execl", "execlp",
    ]

    private static func containsSequence(_ sequence: [String], tokens: [TokenRecord]) -> Bool {
        if sequence.isEmpty || tokens.count < sequence.count {
            return false
        }
        for start in 0...(tokens.count - sequence.count) {
            var matches = true
            for offset in sequence.indices where tokens[start + offset].text != sequence[offset] {
                matches = false
            }
            if matches {
                return true
            }
        }
        return false
    }

    private static func isFileScope(_ token: TokenSyntax) -> Bool {
        var node = Syntax(token)
        while let parent = node.parent {
            let kind = String(describing: parent.kind)
            if kind == "sourceFile" {
                return true
            }
            if kind == "memberBlock" || kind == "codeBlock" || kind == "closureExpr" {
                return false
            }
            node = parent
        }
        return false
    }

    private static func isTypeStaticVar(_ token: TokenSyntax) -> Bool {
        guard token.text == "var" else {
            return false
        }
        var node = Syntax(token)
        while let parent = node.parent {
            if let declaration = parent.as(VariableDeclSyntax.self) {
                return declaration.modifiers.contains { modifier in
                    modifier.name.text == "static" || modifier.name.text == "class"
                }
            }
            node = parent
        }
        return false
    }

    private static func at(
        _ law: LawCode,
        token: TokenRecord,
        source: String,
        path: String
    ) -> LawViolation {
        let point = locationIn(source: source, offset: token.offset)
        return LawViolation(
            law: law,
            location: SourceLocation(file: path, line: point.line, column: point.column),
            subject: token.text
        )
    }

    private static func violation(
        _ law: LawCode,
        file: String,
        subject: String
    ) -> LawViolation {
        LawViolation(
            law: law,
            location: SourceLocation(file: file, line: 1, column: 1),
            subject: subject
        )
    }

    private static func violation(
        _ law: LawCode,
        file: String,
        source: String,
        offset: Int,
        subject: String
    ) -> LawViolation {
        let point = locationIn(source: source, offset: offset)
        return LawViolation(
            law: law,
            location: SourceLocation(file: file, line: point.line, column: point.column),
            subject: subject
        )
    }

    private static func locationIn(source: String, offset: Int) -> (line: Int, column: Int) {
        let bytes = Array(source.utf8)
        let boundedOffset = min(max(offset, 0), bytes.count)
        var line = 1
        var column = 1
        for byte in bytes[0..<boundedOffset] {
            if byte == 10 {
                line += 1
                column = 1
            } else {
                column += 1
            }
        }
        return (line, column)
    }
}

private struct TokenRecord {
    let text: String
    let offset: Int
    let isFileScope: Bool
    let isTypeStaticVar: Bool
    let isForceUnwrap: Bool
}

private struct SourceInventory {
    var paths: [String] = []
    var violations: [LawViolation] = []
}
