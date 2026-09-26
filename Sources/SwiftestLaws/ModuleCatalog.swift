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
    public let systemImports: Set<String>

    public init(
        name: String,
        dependencies: Set<String>,
        role: ModuleRole,
        systemImports: Set<String> = []
    ) {
        self.name = name
        self.dependencies = dependencies
        self.role = role
        self.systemImports = systemImports
    }
}

public enum SwiftestModuleGraph {
    public static let declarations: [ModuleDeclaration] = [
        ModuleDeclaration(name: "SwiftestModel", dependencies: [], role: .production, systemImports: ["Foundation"]),
        ModuleDeclaration(name: "SwiftestFaults", dependencies: ["SwiftestModel"], role: .production, systemImports: ["Foundation"]),
        ModuleDeclaration(name: "SwiftestCodec", dependencies: ["SwiftestModel"], role: .production, systemImports: ["Foundation"]),
        ModuleDeclaration(name: "SwiftestPlatform", dependencies: ["SwiftestModel"], role: .production, systemImports: ["Darwin", "Foundation"]),
        ModuleDeclaration(
            name: "SwiftestStore",
            dependencies: ["SwiftestCodec", "SwiftestModel", "SwiftestPlatform"],
            role: .production,
            systemImports: ["Foundation"]
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
            role: .production,
            systemImports: ["Foundation"]
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
            role: .production,
            systemImports: ["Foundation"]
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
            role: .production,
            systemImports: ["Foundation"]
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
            role: .macro,
            systemImports: ["Foundation", "SwiftParser", "SwiftSyntax"]
        ),
        ModuleDeclaration(
            name: "SwiftestLaws",
            dependencies: ["SwiftestCodec", "SwiftestModel", "SwiftestPlatform"],
            role: .production,
            systemImports: ["Foundation", "SwiftParser", "SwiftParserDiagnostics", "SwiftSyntax"]
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
            role: .executable,
            systemImports: ["Foundation"]
        ),
        ModuleDeclaration(
            name: "SwiftestLawTool",
            dependencies: ["SwiftestLaws", "SwiftestModel", "SwiftestPlatform"],
            role: .executable,
            systemImports: ["Foundation"]
        ),
        ModuleDeclaration(
            name: "SwiftestLawsPlugin",
            dependencies: ["SwiftestLawTool"],
            role: .plugin,
            systemImports: ["Foundation", "PackagePlugin"]
        ),
        ModuleDeclaration(
            name: "SwiftestModelTests",
            dependencies: ["SwiftestModel"],
            role: .test,
            systemImports: ["CryptoKit", "Foundation", "Testing"]
        ),
        ModuleDeclaration(
            name: "SwiftestCodecTests",
            dependencies: ["SwiftestCodec"],
            role: .test,
            systemImports: ["Foundation", "Testing"]
        ),
        ModuleDeclaration(
            name: "SwiftestEngineTests",
            dependencies: [
                "SwiftestEngine",
                "SwiftestFaults",
                "SwiftestModel",
                "SwiftestMutation",
                "SwiftestPlatform",
                "SwiftestScheduler",
                "SwiftestSolver",
            ],
            role: .test,
            systemImports: ["Foundation", "Testing"]
        ),
        ModuleDeclaration(
            name: "SwiftestLawsTests",
            dependencies: ["SwiftestLaws", "SwiftestModel", "SwiftestPlatform"],
            role: .test,
            systemImports: ["Foundation", "Testing"]
        ),
        ModuleDeclaration(
            name: "SwiftestReportTests",
            dependencies: ["SwiftestCodec", "SwiftestDecision", "SwiftestFaults", "SwiftestModel", "SwiftestReport", "SwiftestScore"],
            role: .test,
            systemImports: ["Foundation", "Testing"]
        ),
        ModuleDeclaration(
            name: "SwiftestTestingTests",
            dependencies: ["SwiftestEngine", "SwiftestModel", "SwiftestTesting"],
            role: .test,
            systemImports: ["Testing"]
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

    public static let recognizedSystemModules = Set(declarations.flatMap(\.systemImports))

    public static func permitsSystemImport(
        _ imported: String,
        declaration: ModuleDeclaration,
        relativePath: String
    ) -> Bool {
        guard declaration.systemImports.contains(imported) else {
            return false
        }
        if imported == "Darwin" {
            return declaration.name == "SwiftestPlatform"
                && relativePath == "Sources/SwiftestPlatform/ABIAdapter.swift"
        }
        return true
    }
}
