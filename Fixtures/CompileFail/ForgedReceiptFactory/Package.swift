// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ForgedReceiptFactory",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "ForgedReceiptFactory",
            dependencies: [.product(name: "Swiftest", package: "swiftest")]
        )
    ]
)
