// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ClosedDomainWrongDecl",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "ClosedDomainWrongDecl",
            dependencies: [.product(name: "SwiftestTesting", package: "swiftest")]
        )
    ]
)
