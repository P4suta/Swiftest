// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PropertyMissingTest",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "PropertyMissingTest",
            dependencies: [.product(name: "SwiftestTesting", package: "swiftest")]
        )
    ]
)
