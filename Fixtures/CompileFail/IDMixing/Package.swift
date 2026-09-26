// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "IDMixing",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "IDMixing",
            dependencies: [.product(name: "Swiftest", package: "swiftest")]
        )
    ]
)
