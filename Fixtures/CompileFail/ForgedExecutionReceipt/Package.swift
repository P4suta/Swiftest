// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ForgedExecutionReceipt",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "ForgedExecutionReceipt",
            dependencies: [.product(name: "Swiftest", package: "swiftest")]
        )
    ]
)
