// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ClaimPolarity",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "ClaimPolarity",
            dependencies: [.product(name: "Swiftest", package: "swiftest")]
        )
    ]
)
