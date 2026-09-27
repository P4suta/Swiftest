// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DeclaredClaimsWrongPolarity",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "DeclaredClaimsWrongPolarity",
            dependencies: [.product(name: "Swiftest", package: "swiftest")]
        )
    ]
)
