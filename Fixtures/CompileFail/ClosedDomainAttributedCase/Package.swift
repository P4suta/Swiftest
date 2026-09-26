// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ClosedDomainAttributedCase",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "ClosedDomainAttributedCase",
            dependencies: [.product(name: "SwiftestTesting", package: "swiftest")]
        )
    ]
)
