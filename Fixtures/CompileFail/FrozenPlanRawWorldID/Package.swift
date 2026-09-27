// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FrozenPlanRawWorldID",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "FrozenPlanRawWorldID",
            dependencies: [.product(name: "Swiftest", package: "swiftest")]
        )
    ]
)
