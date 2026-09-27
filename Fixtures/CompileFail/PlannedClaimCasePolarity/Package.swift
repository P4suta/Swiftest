// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PlannedClaimCasePolarity",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "PlannedClaimCasePolarity",
            dependencies: [.product(name: "Swiftest", package: "swiftest")]
        )
    ]
)
