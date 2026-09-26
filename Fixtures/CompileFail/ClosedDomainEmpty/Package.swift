// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ClosedDomainEmpty",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "ClosedDomainEmpty",
            dependencies: [.product(name: "SwiftestTesting", package: "swiftest")]
        )
    ]
)
