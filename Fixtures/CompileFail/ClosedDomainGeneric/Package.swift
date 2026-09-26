// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ClosedDomainGeneric",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "ClosedDomainGeneric",
            dependencies: [.product(name: "SwiftestTesting", package: "swiftest")]
        )
    ]
)
