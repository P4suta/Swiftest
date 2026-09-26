// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CapabilityCopy",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "CapabilityCopy",
            dependencies: [.product(name: "Swiftest", package: "swiftest")]
        )
    ]
)
