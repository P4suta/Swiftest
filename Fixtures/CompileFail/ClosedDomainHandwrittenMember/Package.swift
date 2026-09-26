// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ClosedDomainHandwrittenMember",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "ClosedDomainHandwrittenMember",
            dependencies: [.product(name: "SwiftestTesting", package: "swiftest")]
        )
    ]
)
