// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ForgedBuildReceipt",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "ForgedBuildReceipt",
            dependencies: [.product(name: "Swiftest", package: "swiftest")]
        )
    ]
)
