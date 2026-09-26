import SwiftParser
import SwiftSyntax

enum PackageManifestGraph {
    static func violations(in source: String) -> [LawViolation] {
        let tokens = Parser.parse(source: source).tokens(viewMode: .sourceAccurate)
            .map(\.text).filter { !$0.isEmpty }
        var violations: [LawViolation] = []
        if tokens.contains("#") {
            violations.append(issue(.unclassifiedTarget, subject: "conditional-manifest"))
        }
        for (name, expected) in settingBindings {
            if binding(named: name, in: tokens) != normalizedTokens(expected) {
                violations.append(issue(.unclassifiedTarget, subject: "settings:" + name))
            }
        }
        for index in tokens.indices where tokens[index] == "." {
            if index + 1 < tokens.count && tokens[index + 1] == "package" {
                violations.append(issue(.forbiddenDependency, subject: "external-package"))
            }
        }
        let packageCalls = tokens.indices.filter { index in
            index + 1 < tokens.count && tokens[index] == "Package" && tokens[index + 1] == "("
        }
        guard packageCalls.count == 1,
            let packageEnd = matchingClose(in: tokens, open: packageCalls[0] + 1, opening: "(", closing: ")"),
            let packageArguments = splitTopLevel(Array(tokens[(packageCalls[0] + 2)..<packageEnd])) else {
            violations.append(issue(.unclassifiedTarget, subject: "manifest-targets"))
            return violations
        }
        let expectedPrefix = ["import", "CompilerPluginSupport", "import", "PackageDescription"]
            + settingBindings.flatMap { normalizedTokens($0.declaration) }
            + ["let", "package", "="]
        if Array(tokens[..<packageCalls[0]]) != expectedPrefix || packageEnd + 1 != tokens.count {
            violations.append(issue(.unclassifiedTarget, subject: "manifest-top-level"))
        }
        let packageLabels = packageArguments.compactMap { argument -> String? in
            guard argument.count >= 3, argument[1] == ":" else {
                return nil
            }
            return argument[0]
        }
        let allowedPackageLabels: Set<String> = [
            "name", "platforms", "products", "dependencies", "targets", "swiftLanguageModes",
        ]
        if packageLabels.count != packageArguments.count
            || Set(packageLabels).count != packageLabels.count
            || packageLabels.contains(where: { !allowedPackageLabels.contains($0) }) {
            violations.append(issue(.unclassifiedTarget, subject: "package-arguments"))
        }
        let languageModes = packageArguments.filter { $0.first == "swiftLanguageModes" }
        if languageModes.count != 1
            || languageModes[0] != normalizedTokens("swiftLanguageModes: [.v6]") {
            violations.append(issue(.unclassifiedTarget, subject: "swift-language-mode"))
        }
        let names = packageArguments.filter { $0.first == "name" }
        if names.count != 1 || names[0] != normalizedTokens("name: \"Swiftest\"") {
            violations.append(issue(.unclassifiedTarget, subject: "package-name"))
        }
        let platforms = packageArguments.filter { $0.first == "platforms" }
        if platforms.count != 1 || platforms[0] != normalizedTokens(requiredPlatforms) {
            violations.append(issue(.unclassifiedTarget, subject: "platforms"))
        }
        let products = packageArguments.filter { $0.first == "products" }
        if products.count != 1 || products[0] != normalizedTokens(requiredProducts) {
            violations.append(issue(.unclassifiedTarget, subject: "products"))
        }
        let externalDependencies = packageArguments.filter {
            $0.count >= 2 && $0[0] == "dependencies" && $0[1] == ":"
        }
        if externalDependencies.count > 1
            || externalDependencies.contains(where: { $0 != ["dependencies", ":", "[", "]"] }) {
            violations.append(issue(.forbiddenDependency, subject: "package-dependencies"))
        }
        let targetArguments = packageArguments.filter { $0.count >= 3 && $0[0] == "targets" && $0[1] == ":" }
        guard targetArguments.count == 1,
            targetArguments[0][2] == "[",
            targetArguments[0].last == "]" else {
            violations.append(issue(.unclassifiedTarget, subject: "manifest-targets"))
            return violations
        }
        let contents = Array(targetArguments[0].dropFirst(3).dropLast())
        guard let entries = splitTopLevel(contents) else {
            violations.append(issue(.unclassifiedTarget, subject: "manifest-targets"))
            return violations
        }
        var declared: [String: ManifestTarget] = [:]
        for entry in entries where !entry.isEmpty {
            guard let target = parseTarget(entry) else {
                violations.append(issue(.unclassifiedTarget, subject: "dynamic-target"))
                continue
            }
            if declared.updateValue(target, forKey: target.name) != nil {
                violations.append(issue(.unclassifiedTarget, subject: "duplicate:" + target.name))
            }
        }
        let expected = Dictionary(uniqueKeysWithValues: SwiftestModuleGraph.declarations.map { ($0.name, $0) })
        for declaration in SwiftestModuleGraph.declarations {
            guard let target = declared[declaration.name] else {
                violations.append(issue(.unclassifiedTarget, subject: "missing:" + declaration.name))
                continue
            }
            if target.role != declaration.role {
                violations.append(issue(.unclassifiedTarget, subject: "role:" + declaration.name))
            }
            if !matchesRequiredSettings(target, declaration: declaration) {
                violations.append(issue(.unclassifiedTarget, subject: "settings:" + declaration.name))
            }
            let requiredPlugins: Set<String> = SwiftestModuleGraph.requiresLawPlugin(for: declaration)
                ? ["SwiftestLawsPlugin"]
                : []
            for plugin in target.plugins.subtracting(requiredPlugins) {
                violations.append(issue(
                    plugin == "SwiftestLawsPlugin" ? .reverseDependency : .forbiddenDependency,
                    subject: declaration.name + ":plugin:" + plugin
                ))
            }
            for plugin in requiredPlugins.subtracting(target.plugins) {
                violations.append(issue(.unclassifiedTarget, subject: declaration.name + ":missing-plugin:" + plugin))
            }
            for dependency in target.dependencies.subtracting(declaration.dependencies) {
                violations.append(issue(
                    expected[dependency] == nil ? .forbiddenDependency : .reverseDependency,
                    subject: declaration.name + ":" + dependency
                ))
            }
            for dependency in declaration.dependencies.subtracting(target.dependencies) {
                violations.append(issue(.reverseDependency, subject: declaration.name + ":missing:" + dependency))
            }
        }
        for name in declared.keys where expected[name] == nil {
            violations.append(issue(.unclassifiedTarget, subject: "undeclared:" + name))
        }
        return violations
    }

    private static func parseTarget(_ tokens: [String]) -> ManifestTarget? {
        guard tokens.count >= 5,
            tokens[0] == ".",
            tokens[2] == "(",
            tokens[tokens.count - 1] == ")" else {
            return nil
        }
        let role: ModuleRole
        switch tokens[1] {
        case "target":
            role = .production
        case "executableTarget":
            role = .executable
        case "testTarget":
            role = .test
        case "plugin":
            role = .plugin
        case "macro":
            role = .macro
        default:
            return nil
        }
        guard let arguments = splitTopLevel(Array(tokens[3..<(tokens.count - 1)])) else {
            return nil
        }
        var name: String?
        var dependencies: Set<String> = []
        var foundDependencies = false
        var plugins: Set<String> = []
        var foundPlugins = false
        var swiftSettings: [String]?
        var linkerSettings: [String]?
        var capability: [String]?
        for argument in arguments {
            guard argument.count >= 3, argument[1] == ":" else {
                return nil
            }
            let value = Array(argument.dropFirst(2))
            switch argument[0] {
            case "name":
                if name != nil {
                    return nil
                }
                name = stringLiteral(value)
                if name == nil {
                    return nil
                }
            case "dependencies":
                if foundDependencies {
                    return nil
                }
                foundDependencies = true
                guard value.count >= 2, value.first == "[", value.last == "]",
                    let items = splitTopLevel(Array(value.dropFirst().dropLast())) else {
                    return nil
                }
                for item in items where !item.isEmpty {
                    guard let dependency = stringLiteral(item), !dependencies.contains(dependency) else {
                        return nil
                    }
                    dependencies.insert(dependency)
                }
            case "plugins":
                if foundPlugins {
                    return nil
                }
                foundPlugins = true
                guard value.count >= 2, value.first == "[", value.last == "]",
                    let items = splitTopLevel(Array(value.dropFirst().dropLast())) else {
                    return nil
                }
                for item in items where !item.isEmpty {
                    guard let plugin = stringLiteral(item), !plugins.contains(plugin) else {
                        return nil
                    }
                    plugins.insert(plugin)
                }
            case "swiftSettings":
                if swiftSettings != nil {
                    return nil
                }
                swiftSettings = value
            case "linkerSettings":
                if linkerSettings != nil {
                    return nil
                }
                linkerSettings = value
            case "capability":
                if capability != nil {
                    return nil
                }
                capability = value
            case "path", "sources", "exclude", "publicHeadersPath":
                return nil
            default:
                return nil
            }
        }
        guard let name else {
            return nil
        }
        return ManifestTarget(
            name: name,
            dependencies: dependencies,
            plugins: plugins,
            role: role,
            swiftSettings: swiftSettings,
            linkerSettings: linkerSettings,
            capability: capability
        )
    }

    private static let settingBindings: [(name: String, declaration: String)] = [
        (
            "strict",
            "let strict: [SwiftSetting] = [.unsafeFlags([\"-warnings-as-errors\", \"-strict-concurrency=complete\"]),]"
        ),
        (
            "hostSwiftSyntax",
            "let hostSwiftSyntax: [SwiftSetting] = [.unsafeFlags([\"-warnings-as-errors\", \"-strict-concurrency=complete\", \"-I\", \"/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host\",]),]"
        ),
        (
            "hostSwiftSyntaxLinker",
            "let hostSwiftSyntaxLinker: [LinkerSetting] = [.unsafeFlags([\"-L\", \"/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host\", \"-Xlinker\", \"-rpath\", \"-Xlinker\", \"/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host\",]),]"
        ),
    ]

    private static let requiredPlatforms = "platforms: ["
        + ".macOS(.v14), .iOS(.v17), .tvOS(.v17), .watchOS(.v10), .visionOS(.v1),"
        + "]"

    private static let requiredProducts = "products: ["
        + ".library(name: \"Swiftest\", targets: [\"Swiftest\"]),"
        + ".library(name: \"SwiftestTesting\", targets: [\"SwiftestTesting\"]),"
        + ".library(name: \"SwiftestLaws\", targets: [\"SwiftestLaws\"]),"
        + ".executable(name: \"swiftest\", targets: [\"SwiftestCLI\"]),"
        + ".plugin(name: \"SwiftestLawsPlugin\", targets: [\"SwiftestLawsPlugin\"]),"
        + "]"

    private static let hostSettingsTargets: Set<String> = [
        "SwiftestMacros", "SwiftestLaws", "SwiftestCLI", "SwiftestLawTool", "SwiftestLawsTests",
    ]

    private static func matchesRequiredSettings(
        _ target: ManifestTarget,
        declaration: ModuleDeclaration
    ) -> Bool {
        if declaration.role == .plugin {
            return target.swiftSettings == nil
                && target.linkerSettings == nil
                && target.capability == normalizedTokens(".buildTool()")
        }
        if target.capability != nil {
            return false
        }
        if hostSettingsTargets.contains(declaration.name) {
            return target.swiftSettings == ["hostSwiftSyntax"]
                && target.linkerSettings == ["hostSwiftSyntaxLinker"]
        }
        if declaration.name == "SwiftestPlatform" {
            return target.swiftSettings == ["strict"]
                && target.linkerSettings == normalizedTokens("[.linkedFramework(\"Security\")]")
        }
        return target.swiftSettings == ["strict"] && target.linkerSettings == nil
    }

    private static func binding(named name: String, in tokens: [String]) -> [String]? {
        let starts = tokens.indices.filter { index in
            index + 1 < tokens.count && tokens[index] == "let" && tokens[index + 1] == name
        }
        guard starts.count == 1 else {
            return nil
        }
        let start = starts[0]
        guard let equals = tokens[(start + 2)...].firstIndex(of: "="),
            equals + 1 < tokens.count,
            tokens[equals + 1] == "[",
            let end = matchingClose(in: tokens, open: equals + 1, opening: "[", closing: "]") else {
            return nil
        }
        return Array(tokens[start...end])
    }

    private static func normalizedTokens(_ source: String) -> [String] {
        Parser.parse(source: source).tokens(viewMode: .sourceAccurate)
            .map(\.text).filter { !$0.isEmpty }
    }

    private static func stringLiteral(_ tokens: [String]) -> String? {
        guard tokens.count == 3, tokens[0] == "\"", tokens[2] == "\"", !tokens[1].isEmpty else {
            return nil
        }
        return tokens[1]
    }

    private static func matchingClose(
        in tokens: [String],
        open: Int,
        opening: String,
        closing: String
    ) -> Int? {
        var depth = 0
        for index in open..<tokens.count {
            if tokens[index] == opening {
                depth += 1
            } else if tokens[index] == closing {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
        }
        return nil
    }

    private static func splitTopLevel(_ tokens: [String]) -> [[String]]? {
        var segments: [[String]] = []
        var current: [String] = []
        var parentheses = 0
        var brackets = 0
        var braces = 0
        for token in tokens {
            if token == "," && parentheses == 0 && brackets == 0 && braces == 0 {
                segments.append(current)
                current = []
                continue
            }
            switch token {
            case "(":
                parentheses += 1
            case ")":
                parentheses -= 1
            case "[":
                brackets += 1
            case "]":
                brackets -= 1
            case "{":
                braces += 1
            case "}":
                braces -= 1
            default:
                break
            }
            if parentheses < 0 || brackets < 0 || braces < 0 {
                return nil
            }
            current.append(token)
        }
        if parentheses != 0 || brackets != 0 || braces != 0 {
            return nil
        }
        if !current.isEmpty {
            segments.append(current)
        }
        return segments
    }

    private static func issue(_ law: LawCode, subject: String) -> LawViolation {
        LawViolation(
            law: law,
            location: SourceLocation(file: "Package.swift", line: 1, column: 1),
            subject: subject
        )
    }
}

private struct ManifestTarget {
    let name: String
    let dependencies: Set<String>
    let plugins: Set<String>
    let role: ModuleRole
    let swiftSettings: [String]?
    let linkerSettings: [String]?
    let capability: [String]?
}
