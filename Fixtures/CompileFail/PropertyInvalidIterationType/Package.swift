// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PropertyInvalidIterationType",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "PropertyInvalidIterationType",
            dependencies: [.product(name: "SwiftestTesting", package: "swiftest")]
        )
    ]
)
