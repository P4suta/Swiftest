import SwiftParser
import SwiftSyntax

enum ExternalSwiftLanguageMode: Sendable {
    case declaredSwift6
    case undeclared
}

struct ExternalPackageTarget: Sendable {
    let name: String
    let role: ModuleRole
    let dependencies: Set<String>
}

struct ExternalPackageManifest: Sendable {
    let name: String
    let targets: [ExternalPackageTarget]
    let languageMode: ExternalSwiftLanguageMode

    static func parse(_ source: String) -> ExternalPackageManifest? {
        let tokens = Parser.parse(source: source).tokens(viewMode: .sourceAccurate)
            .map(\.text).filter { !$0.isEmpty }
        let prefix = ["import", "PackageDescription", "let", "package", "=", "Package", "("]
        guard tokens.count > prefix.count,
            Array(tokens.prefix(prefix.count)) == prefix,
            let close = matchingClose(tokens, open: prefix.count - 1, opening: "(", closing: ")"),
            close == tokens.count - 1,
            let arguments = labeledArguments(Array(tokens[prefix.count..<close])) else {
            return nil
        }
        let allowed: Set<String> = [
            "name", "platforms", "products", "dependencies", "targets", "swiftLanguageModes",
        ]
        guard Set(arguments.keys).isSubset(of: allowed),
            let nameTokens = arguments["name"],
            let name = stringLiteral(nameTokens),
            validName(name),
            let targetTokens = arguments["targets"],
            let targetItems = arrayElements(targetTokens),
            !targetItems.isEmpty else {
            return nil
        }
        if let platforms = arguments["platforms"], !validPlatforms(platforms) {
            return nil
        }
        if let products = arguments["products"], products != ["[", "]"] {
            return nil
        }
        if let dependencies = arguments["dependencies"], dependencies != ["[", "]"] {
            return nil
        }
        let languageMode: ExternalSwiftLanguageMode
        if let modes = arguments["swiftLanguageModes"] {
            guard modes == ["[", ".", "v6", "]"] else {
                return nil
            }
            languageMode = .declaredSwift6
        } else {
            languageMode = .undeclared
        }
        var targets: [ExternalPackageTarget] = []
        var seen = Set<String>()
        for item in targetItems {
            guard let target = parseTarget(item), seen.insert(target.name).inserted else {
                return nil
            }
            targets.append(target)
        }
        let targetNames = Set(targets.map(\.name))
        for target in targets where !target.dependencies.isSubset(of: targetNames.subtracting([target.name])) {
            return nil
        }
        return ExternalPackageManifest(name: name, targets: targets, languageMode: languageMode)
    }

    private static func parseTarget(_ tokens: [String]) -> ExternalPackageTarget? {
        guard tokens.count >= 6,
            tokens[0] == ".",
            tokens[2] == "(",
            tokens.last == ")",
            let arguments = labeledArguments(Array(tokens[3..<(tokens.count - 1)])),
            let nameTokens = arguments["name"],
            let name = stringLiteral(nameTokens),
            validName(name),
            Set(arguments.keys).isSubset(of: ["name", "dependencies"]) else {
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
        default:
            return nil
        }
        var dependencies = Set<String>()
        if let dependencyTokens = arguments["dependencies"] {
            guard let elements = arrayElements(dependencyTokens) else {
                return nil
            }
            for element in elements {
                guard let dependency = stringLiteral(element),
                    validName(dependency),
                    dependencies.insert(dependency).inserted else {
                    return nil
                }
            }
        }
        return ExternalPackageTarget(name: name, role: role, dependencies: dependencies)
    }

    private static func validPlatforms(_ tokens: [String]) -> Bool {
        guard let platforms = arrayElements(tokens), !platforms.isEmpty else {
            return false
        }
        let names: Set<String> = ["macOS", "iOS", "tvOS", "watchOS", "visionOS"]
        var seen = Set<String>()
        for platform in platforms {
            guard platform.count == 6,
                platform[0] == ".",
                names.contains(platform[1]),
                seen.insert(platform[1]).inserted,
                platform[2] == "(",
                platform[3] == ".",
                platform[4].first == "v",
                platform[4].dropFirst().allSatisfy({ $0.isNumber || $0 == "_" }),
                platform[5] == ")" else {
                return false
            }
        }
        return true
    }

    private static func validName(_ name: String) -> Bool {
        guard let first = name.first, first.isLetter || first == "_" else {
            return false
        }
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private static func stringLiteral(_ tokens: [String]) -> String? {
        guard tokens.count == 3, tokens[0] == "\"", tokens[2] == "\"", !tokens[1].isEmpty else {
            return nil
        }
        return tokens[1]
    }

    private static func arrayElements(_ tokens: [String]) -> [[String]]? {
        guard tokens.first == "[", tokens.last == "]" else {
            return nil
        }
        return splitTopLevel(Array(tokens.dropFirst().dropLast()))
    }

    private static func labeledArguments(_ tokens: [String]) -> [String: [String]]? {
        guard let arguments = splitTopLevel(tokens) else {
            return nil
        }
        var result: [String: [String]] = [:]
        for argument in arguments {
            guard argument.count >= 3,
                argument[1] == ":",
                result[argument[0]] == nil else {
                return nil
            }
            result[argument[0]] = Array(argument.dropFirst(2))
        }
        return result
    }

    private static func matchingClose(
        _ tokens: [String],
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
        if tokens.isEmpty {
            return []
        }
        var result: [[String]] = []
        var current: [String] = []
        var parentheses = 0
        var brackets = 0
        var braces = 0
        for token in tokens {
            if token == "," && parentheses == 0 && brackets == 0 && braces == 0 {
                guard !current.isEmpty else {
                    return nil
                }
                result.append(current)
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
        guard parentheses == 0, brackets == 0, braces == 0 else {
            return nil
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }
}
