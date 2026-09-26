// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ClosedDomainConditionalCase",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "ClosedDomainConditionalCase",
            dependencies: [.product(name: "SwiftestTesting", package: "swiftest")]
        )
    ]
)
