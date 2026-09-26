// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "InvalidTransition",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "InvalidTransition",
            dependencies: [.product(name: "Swiftest", package: "swiftest")]
        )
    ]
)
