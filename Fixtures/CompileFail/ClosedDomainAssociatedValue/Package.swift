// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ClosedDomainAssociatedValue",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "ClosedDomainAssociatedValue",
            dependencies: [.product(name: "SwiftestTesting", package: "swiftest")]
        )
    ]
)
