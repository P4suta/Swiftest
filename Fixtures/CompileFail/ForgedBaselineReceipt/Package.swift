// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ForgedBaselineReceipt",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "ForgedBaselineReceipt",
            dependencies: [.product(name: "Swiftest", package: "swiftest")]
        )
    ]
)
