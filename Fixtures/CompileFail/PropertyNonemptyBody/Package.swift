// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PropertyNonemptyBody",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "PropertyNonemptyBody",
            dependencies: [.product(name: "SwiftestTesting", package: "swiftest")]
        )
    ]
)
