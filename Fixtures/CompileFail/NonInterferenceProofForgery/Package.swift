// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "NonInterferenceProofForgery",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "NonInterferenceProofForgery",
            dependencies: [.product(name: "Swiftest", package: "swiftest")]
        )
    ]
)
