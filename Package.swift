// swift-tools-version: 6.2

import CompilerPluginSupport
import PackageDescription

let strict: [SwiftSetting] = [
    .unsafeFlags(["-warnings-as-errors", "-strict-concurrency=complete"]),
]

let hostSwiftSyntax: [SwiftSetting] = [
    .unsafeFlags([
        "-warnings-as-errors",
        "-strict-concurrency=complete",
        "-I",
        "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host",
    ]),
]

let hostSwiftSyntaxLinker: [LinkerSetting] = [
    .unsafeFlags([
        "-L",
        "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host",
        "-Xlinker",
        "-rpath",
        "-Xlinker",
        "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host",
    ]),
]

let package = Package(
    name: "Swiftest",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "Swiftest", targets: ["Swiftest"]),
        .library(name: "SwiftestTesting", targets: ["SwiftestTesting"]),
        .library(name: "SwiftestLaws", targets: ["SwiftestLaws"]),
        .executable(name: "swiftest", targets: ["SwiftestCLI"]),
        .plugin(name: "SwiftestLawsPlugin", targets: ["SwiftestLawsPlugin"]),
    ],
    targets: [
        .target(name: "SwiftestModel", swiftSettings: strict),
        .target(name: "SwiftestFaults", dependencies: ["SwiftestModel"], swiftSettings: strict),
        .target(name: "SwiftestCodec", dependencies: ["SwiftestModel"], swiftSettings: strict),
        .target(
            name: "SwiftestPlatform",
            dependencies: ["SwiftestModel"],
            swiftSettings: strict,
            linkerSettings: [.linkedFramework("Security")]
        ),
        .target(
            name: "SwiftestStore",
            dependencies: ["SwiftestCodec", "SwiftestModel", "SwiftestPlatform"],
            swiftSettings: strict
        ),
        .target(name: "SwiftestSolver", dependencies: ["SwiftestModel"], swiftSettings: strict),
        .target(
            name: "SwiftestScheduler",
            dependencies: ["SwiftestModel", "SwiftestSolver"],
            swiftSettings: strict
        ),
        .target(
            name: "SwiftestMutation",
            dependencies: ["SwiftestModel", "SwiftestPlatform"],
            swiftSettings: strict
        ),
        .target(
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
            swiftSettings: strict
        ),
        .target(name: "SwiftestDecision", dependencies: ["SwiftestModel"], swiftSettings: strict),
        .target(name: "SwiftestScore", dependencies: ["SwiftestModel"], swiftSettings: strict),
        .target(
            name: "SwiftestReport",
            dependencies: [
                "SwiftestCodec",
                "SwiftestDecision",
                "SwiftestFaults",
                "SwiftestModel",
                "SwiftestScore",
                "SwiftestStore",
            ],
            swiftSettings: strict
        ),
        .target(
            name: "SwiftestPresentation",
            dependencies: ["SwiftestDecision", "SwiftestModel", "SwiftestReport", "SwiftestScore"],
            swiftSettings: strict
        ),
        .target(
            name: "SwiftestTesting",
            dependencies: ["SwiftestEngine", "SwiftestFaults", "SwiftestModel", "SwiftestPlatform"],
            swiftSettings: strict
        ),
        .target(
            name: "SwiftestLaws",
            dependencies: ["SwiftestCodec", "SwiftestModel", "SwiftestPlatform"],
            swiftSettings: hostSwiftSyntax,
            linkerSettings: hostSwiftSyntaxLinker
        ),
        .target(
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
            swiftSettings: strict
        ),
        .executableTarget(
            name: "SwiftestCLI",
            dependencies: [
                "Swiftest",
                "SwiftestCodec",
                "SwiftestLaws",
                "SwiftestPlatform",
                "SwiftestReport",
                "SwiftestStore",
            ],
            swiftSettings: hostSwiftSyntax,
            linkerSettings: hostSwiftSyntaxLinker,
            plugins: ["SwiftestLawsPlugin"]
        ),
        .executableTarget(
            name: "SwiftestLawTool",
            dependencies: ["SwiftestLaws", "SwiftestModel", "SwiftestPlatform"],
            swiftSettings: hostSwiftSyntax,
            linkerSettings: hostSwiftSyntaxLinker
        ),
        .plugin(
            name: "SwiftestLawsPlugin",
            capability: .buildTool(),
            dependencies: ["SwiftestLawTool"]
        ),
        .testTarget(name: "SwiftestModelTests", dependencies: ["SwiftestModel"], swiftSettings: strict),
        .testTarget(name: "SwiftestCodecTests", dependencies: ["SwiftestCodec"], swiftSettings: strict),
        .testTarget(
            name: "SwiftestEngineTests",
            dependencies: [
                "SwiftestEngine",
                "SwiftestFaults",
                "SwiftestModel",
                "SwiftestMutation",
                "SwiftestScheduler",
                "SwiftestSolver",
            ],
            swiftSettings: strict
        ),
        .testTarget(
            name: "SwiftestLawsTests",
            dependencies: ["SwiftestLaws"],
            swiftSettings: hostSwiftSyntax,
            linkerSettings: hostSwiftSyntaxLinker
        ),
        .testTarget(
            name: "SwiftestReportTests",
            dependencies: ["SwiftestCodec", "SwiftestDecision", "SwiftestFaults", "SwiftestModel", "SwiftestReport", "SwiftestScore"],
            swiftSettings: strict
        ),
        .testTarget(
            name: "SwiftestTestingTests",
            dependencies: ["SwiftestModel", "SwiftestTesting"],
            swiftSettings: strict
        ),
    ],
    swiftLanguageModes: [.v6]
)
