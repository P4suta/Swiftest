import Foundation
import SwiftParser
import SwiftParserDiagnostics
import SwiftSyntax
import SwiftestModel
import SwiftestPlatform

public enum LawScanner {
    public static func scan(root: String) throws(LawScannerError) -> LawReport {
        let normalizedRoot = URL(fileURLWithPath: root).standardizedFileURL.path
        if normalizedRoot.isEmpty {
            throw .invalidRoot(root)
        }
        let paths: [String]
        do {
            paths = try sourceFiles(root: normalizedRoot)
        } catch let error {
            throw .platform(String(describing: error))
        }
        var violations: [LawViolation] = []
        for path in paths {
            let relative = relativePath(path, root: normalizedRoot)
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
        }
        violations.append(contentsOf: validateModuleGraph(paths: paths, root: normalizedRoot))
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
            return $0.law.rawValue < $1.law.rawValue
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
            let leadingOffset = token.position.utf8Offset
            for trivia in token.leadingTrivia {
                guard let text = commentText(trivia) else {
                    continue
                }
                if !isAllowedComment(text: text, path: path, source: source, offset: leadingOffset) {
                    violations.append(violation(
                        .forbiddenComment,
                        file: path,
                        source: source,
                        offset: leadingOffset,
                        subject: commentKind(text)
                    ))
                }
            }
            for trivia in token.trailingTrivia {
                guard let text = commentText(trivia) else {
                    continue
                }
                violations.append(violation(
                    .forbiddenComment,
                    file: path,
                    source: source,
                    offset: token.endPositionBeforeTrailingTrivia.utf8Offset,
                    subject: commentKind(text)
                ))
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
                isForceUnwrap: token.tokenKind == .exclamationMark
            )
        }
        violations.append(contentsOf: tokenViolations(records, source: source, path: path))
        return violations
    }

    private static func scanFile(relativePath: String, source: String, data: Data) -> [LawViolation] {
        if relativePath.hasSuffix(".swift") {
            return scanSwiftSource(source, path: relativePath)
        }
        if relativePath.hasSuffix(".md") {
            return [violation(.handwrittenDocumentation, file: relativePath, subject: "markdown")]
        }
        let flavor: SourceFlavor
        if relativePath.hasSuffix(".lean") {
            flavor = .lean
        } else if relativePath.hasSuffix(".json") {
            flavor = .json
        } else if relativePath.hasSuffix(".yml")
            || relativePath.hasSuffix(".yaml")
            || relativePath.hasSuffix(".toml")
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
        let platformBoundary = path.contains("Sources/SwiftestPlatform/")
        let abiBoundary = path.hasSuffix(AuditedBoundary.platformABI.rawValue)
        let testingBoundary = path.hasSuffix(AuditedBoundary.testingStableABI.rawValue)
        let hasClosedDomain = containsSequence(["@", "ClosedDomain"], tokens: tokens)
        for index in tokens.indices {
            let token = tokens[index]
            let previous = index > 0 ? tokens[index - 1].text : ""
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
            if token.text == "var" && token.isFileScope {
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
            if (token.text == "FileManager"
                || token.text == "createDirectory"
                || token.text == "removeItem"
                || token.text == "moveItem"
                || (previous == "." && token.text == "write" && next == "(" && nextTwo == "to"))
                && !platformBoundary {
                violations.append(at(.directFileWrite, token: token, source: source, path: path))
            }
            if (token.text.hasPrefix("withUnsafe")
                || token.text.hasPrefix("UnsafePointer")
                || token.text == "unsafeBitCast"
                || (token.text == "unchecked" && previous == "@"))
                && !abiBoundary {
                violations.append(at(.unsafeOutsideBoundary, token: token, source: source, path: path))
            }
        }
        if containsSequence(["#", "externalMacro"], tokens: tokens) {
            let testingMacroReference = path == "Sources/SwiftestTesting/Macros.swift"
                && source.contains("#externalMacro(module: \"TestingMacros\"")
            if !testingMacroReference {
                violations.append(violation(.uninspectedMacro, file: path, subject: "external-macro"))
            }
        }
        return violations
    }

    private static func validateModuleGraph(paths: [String], root: String) -> [LawViolation] {
        let declarations = Dictionary(uniqueKeysWithValues: SwiftestModuleGraph.declarations.map { ($0.name, $0) })
        var violations: [LawViolation] = []
        let targetRoots = ["Sources", "Tests", "Plugins"]
        for targetRoot in targetRoots {
            let path = root + "/" + targetRoot
            let entries: [String]
            do {
                entries = try FileSystemBoundary.list(path: path)
            } catch {
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
        for path in paths where path.hasSuffix(".swift") {
            let relative = relativePath(path, root: root)
            guard let module = moduleName(relativePath: relative) else {
                continue
            }
            guard let declaration = declarations[module] else {
                continue
            }
            let data: Data
            do {
                data = try FileSystemBoundary.read(path: path)
            } catch {
                continue
            }
            guard let source = String(data: data, encoding: .utf8) else {
                continue
            }
            let imports = importedModules(source)
            for imported in imports {
                if SwiftestModuleGraph.systemModules.contains(imported) {
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
        for index in texts.indices where texts[index] == "import" && index + 1 < texts.count {
            imports.insert(texts[index + 1])
        }
        return imports
    }

    private static func sourceFiles(root: String) throws(PlatformError) -> [String] {
        var result: [String] = []
        try walk(path: root, result: &result)
        return result.sorted()
    }

    private static func walk(path: String, result: inout [String]) throws(PlatformError) {
        let kind = try FileSystemBoundary.entryKind(path: path)
        switch kind {
        case .file:
            if shouldScan(path) {
                result.append(path)
            }
        case .directory:
            let name = URL(fileURLWithPath: path).lastPathComponent
            if ignoredDirectory(name) {
                return
            }
            for entry in try FileSystemBoundary.list(path: path) {
                try walk(path: path + "/" + entry, result: &result)
            }
        case .symbolicLink, .other:
            break
        }
    }

    private static func shouldScan(_ path: String) -> Bool {
        let name = URL(fileURLWithPath: path).lastPathComponent
        let extensions = ["swift", "json", "yml", "yaml", "toml", "lean"]
        if extensions.contains(URL(fileURLWithPath: path).pathExtension) {
            return true
        }
        return name == "lean-toolchain"
            || name == "quality"
            || name == "formal-check"
            || name == "compile-fail"
            || name == "dogfood"
            || name == "platform-check"
            || path.contains("/.githooks/")
    }

    private static func ignoredDirectory(_ name: String) -> Bool {
        name == ".git"
            || name == ".build"
            || name == ".swiftpm"
            || name == "DerivedData"
    }

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
            && text.hasPrefix("// swift-tools-version:") {
            return true
        }
        if location.line <= 5
            && (text == "// SPDX-License-Identifier: Apache-2.0"
                || text == "// SPDX-License-Identifier: MIT") {
            return true
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
    let isForceUnwrap: Bool
}
