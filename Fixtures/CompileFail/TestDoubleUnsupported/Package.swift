// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "TestDoubleUnsupported",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "TestDoubleUnsupported",
            dependencies: [.product(name: "SwiftestTesting", package: "swiftest")]
        )
    ]
)
