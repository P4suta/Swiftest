// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DeclaredClaimsRawID",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "DeclaredClaimsRawID",
            dependencies: [.product(name: "Swiftest", package: "swiftest")]
        )
    ]
)
