// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PerformanceClaimUnsupported",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "PerformanceClaimUnsupported",
            dependencies: [.product(name: "SwiftestTesting", package: "swiftest")]
        )
    ]
)
