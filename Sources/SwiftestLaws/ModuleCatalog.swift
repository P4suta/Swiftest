public enum ModuleRole: String, CaseIterable, Sendable {
    case production
    case executable
    case test
    case plugin
    case macro
}

public struct ModuleDeclaration: Hashable, Sendable {
    public let name: String
    public let dependencies: Set<String>
    public let role: ModuleRole

    public init(name: String, dependencies: Set<String>, role: ModuleRole) {
        self.name = name
        self.dependencies = dependencies
        self.role = role
    }
}

public enum SwiftestModuleGraph {
    public static let declarations: [ModuleDeclaration] = [
        ModuleDeclaration(name: "SwiftestModel", dependencies: [], role: .production),
        ModuleDeclaration(name: "SwiftestFaults", dependencies: ["SwiftestModel"], role: .production),
        ModuleDeclaration(name: "SwiftestCodec", dependencies: ["SwiftestModel"], role: .production),
        ModuleDeclaration(name: "SwiftestPlatform", dependencies: ["SwiftestModel"], role: .production),
        ModuleDeclaration(
            name: "SwiftestStore",
            dependencies: ["SwiftestCodec", "SwiftestModel", "SwiftestPlatform"],
            role: .production
        ),
        ModuleDeclaration(name: "SwiftestSolver", dependencies: ["SwiftestModel"], role: .production),
        ModuleDeclaration(
            name: "SwiftestScheduler",
            dependencies: ["SwiftestModel", "SwiftestSolver"],
            role: .production
        ),
        ModuleDeclaration(
            name: "SwiftestMutation",
            dependencies: ["SwiftestModel", "SwiftestPlatform"],
            role: .production
        ),
        ModuleDeclaration(
            name: "SwiftestEngine",
            dependencies: [
                "SwiftestCodec",
                "SwiftestFaults",
                "SwiftestModel",
                "SwiftestMutation",
                "SwiftestPlatform",
                "SwiftestScheduler",
                "SwiftestSolver",
                "SwiftestStore",
            ],
            role: .production
        ),
        ModuleDeclaration(name: "SwiftestDecision", dependencies: ["SwiftestModel"], role: .production),
        ModuleDeclaration(name: "SwiftestScore", dependencies: ["SwiftestModel"], role: .production),
        ModuleDeclaration(
            name: "SwiftestReport",
            dependencies: [
                "SwiftestCodec",
                "SwiftestDecision",
                "SwiftestFaults",
                "SwiftestModel",
                "SwiftestScore",
                "SwiftestStore",
            ],
            role: .production
        ),
        ModuleDeclaration(
            name: "SwiftestPresentation",
            dependencies: ["SwiftestDecision", "SwiftestModel", "SwiftestReport", "SwiftestScore"],
            role: .production
        ),
        ModuleDeclaration(
            name: "SwiftestTesting",
            dependencies: ["SwiftestEngine", "SwiftestFaults", "SwiftestMacros", "SwiftestModel", "SwiftestPlatform"],
            role: .production
        ),
        ModuleDeclaration(
            name: "SwiftestMacros",
            dependencies: ["SwiftestCodec"],
            role: .macro
        ),
        ModuleDeclaration(
            name: "SwiftestLaws",
            dependencies: ["SwiftestCodec", "SwiftestModel", "SwiftestPlatform"],
            role: .production
        ),
        ModuleDeclaration(
            name: "Swiftest",
            dependencies: [
                "SwiftestDecision",
                "SwiftestEngine",
                "SwiftestFaults",
                "SwiftestModel",
                "SwiftestMutation",
                "SwiftestPlatform",
                "SwiftestPresentation",
                "SwiftestReport",
                "SwiftestScheduler",
                "SwiftestScore",
                "SwiftestSolver",
                "SwiftestStore",
                "SwiftestTesting",
            ],
            role: .production
        ),
        ModuleDeclaration(
            name: "SwiftestCLI",
            dependencies: [
                "Swiftest",
                "SwiftestCodec",
                "SwiftestLaws",
                "SwiftestPlatform",
                "SwiftestReport",
                "SwiftestStore",
            ],
            role: .executable
        ),
        ModuleDeclaration(
            name: "SwiftestLawTool",
            dependencies: ["SwiftestLaws", "SwiftestModel", "SwiftestPlatform"],
            role: .executable
        ),
        ModuleDeclaration(
            name: "SwiftestLawsPlugin",
            dependencies: ["SwiftestLawTool"],
            role: .plugin
        ),
        ModuleDeclaration(name: "SwiftestModelTests", dependencies: ["SwiftestModel"], role: .test),
        ModuleDeclaration(name: "SwiftestCodecTests", dependencies: ["SwiftestCodec"], role: .test),
        ModuleDeclaration(
            name: "SwiftestEngineTests",
            dependencies: [
                "SwiftestEngine",
                "SwiftestFaults",
                "SwiftestModel",
                "SwiftestMutation",
                "SwiftestScheduler",
                "SwiftestSolver",
            ],
            role: .test
        ),
        ModuleDeclaration(
            name: "SwiftestLawsTests",
            dependencies: ["SwiftestLaws", "SwiftestModel", "SwiftestPlatform"],
            role: .test
        ),
        ModuleDeclaration(
            name: "SwiftestReportTests",
            dependencies: ["SwiftestCodec", "SwiftestDecision", "SwiftestFaults", "SwiftestModel", "SwiftestReport", "SwiftestScore"],
            role: .test
        ),
        ModuleDeclaration(
            name: "SwiftestTestingTests",
            dependencies: ["SwiftestEngine", "SwiftestModel", "SwiftestTesting"],
            role: .test
        ),
    ]

    public static func requiresLawPlugin(for declaration: ModuleDeclaration) -> Bool {
        if declaration.role == .plugin {
            return false
        }
        var pluginDependencyClosure: Set<String> = ["SwiftestLawsPlugin"]
        var changed = true
        while changed {
            changed = false
            for module in declarations where pluginDependencyClosure.contains(module.name) {
                let previousCount = pluginDependencyClosure.count
                pluginDependencyClosure.formUnion(module.dependencies)
                if pluginDependencyClosure.count != previousCount {
                    changed = true
                }
            }
        }
        return !pluginDependencyClosure.contains(declaration.name)
    }

    public static let systemModules: Set<String> = [
        "CryptoKit",
        "Darwin",
        "Foundation",
        "PackagePlugin",
        "SwiftParser",
        "SwiftParserDiagnostics",
        "SwiftSyntax",
        "Testing",
    ]
}
