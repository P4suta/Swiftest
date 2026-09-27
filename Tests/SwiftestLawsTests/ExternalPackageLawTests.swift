import Foundation
import SwiftestLaws
import SwiftestModel
import SwiftestPlatform
import Testing

private func externalPackageScratch() throws -> ScratchDirectoryOwner {
    try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-external-laws-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
}

private func writeExternalSource(
    _ source: String,
    path: String,
    scratch: borrowing ScratchDirectoryOwner
) throws {
    let relative = try ArtifactPath.parse(path)
    try FileSystemBoundary.write(
        Data(source.utf8),
        relativePath: relative,
        capability: scratch.issueWriteCapability()
    )
}

private func externalManifest(
    targetName: String,
    targetKind: String,
    languageModes: String
) -> String {
    """
    // swift-tools-version: 6.2
    import PackageDescription

    let package = Package(
        name: "Fixture",
        platforms: [.macOS(.v14)],
        targets: [.\(targetKind)(name: "\(targetName)")],
        \(languageModes)
    )
    """
}

private func findingStatus(_ code: LawCode, in assessment: TargetLawAssessment) -> TargetLawStatus? {
    assessment.findings.first { $0.code == code }?.status
}

@Test
func externalPackageLawsDoNotApplySwiftestOwnedGraph() throws {
    let scratch = try externalPackageScratch()
    try writeExternalSource(
        externalManifest(targetName: "SmokeTests", targetKind: "testTarget", languageModes: ""),
        path: "Package.swift",
        scratch: scratch
    )
    try writeExternalSource(
        "import Testing\n@Test func modernPasses() { #expect(true) }\n",
        path: "Tests/SmokeTests/ModernTests.swift",
        scratch: scratch
    )
    try writeExternalSource(
        "import XCTest\nfinal class LegacyTests: XCTestCase { func testPass() { XCTAssertTrue(true) } }\n",
        path: "Tests/SmokeTests/LegacyTests.swift",
        scratch: scratch
    )
    let assessment = try LawScanner.scanExternalSwiftPackage(root: scratch.path)
    #expect(assessment.report.violations.isEmpty)
    #expect(assessment.findings.count == LawCode.allCases.count)
    #expect(Set(assessment.findings.map(\.code)) == Set(LawCode.allCases))
    #expect(findingStatus(.forbiddenComment, in: assessment) == .passed)
    #expect(findingStatus(.toolchainMismatch, in: assessment) == .unassessed(.swift6ModeUndeclared))
    #expect(findingStatus(.missingExternalProof, in: assessment) == .unassessed(.externalProofMissing))
    #expect(assessment.lawObservations.count == LawCode.allCases.count)
    #expect(assessment.lawObservations.contains {
        $0.code == .toolchainMismatch && $0.status == .failed && $0.diagnostic?.code == .missingEvidence
    })
}

@Test
func externalPackageLawsRejectManifestResourcesAndUnknownImports() throws {
    let scratch = try externalPackageScratch()
    try writeExternalSource(
        externalManifest(targetName: "Core", targetKind: "target", languageModes: "swiftLanguageModes: [.v6],\n"),
        path: "Package.swift",
        scratch: scratch
    )
    try writeExternalSource(
        "import MysteryDependency\nlet value = 1\n",
        path: "Sources/Core/Core.swift",
        scratch: scratch
    )
    try writeExternalSource("{}\n", path: "Sources/Core/Resources/data.json", scratch: scratch)
    let assessment = try LawScanner.scanExternalSwiftPackage(root: scratch.path)
    #expect(assessment.report.violations.contains {
        $0.law == .forbiddenDependency && $0.subject == "MysteryDependency"
    })
    #expect(assessment.report.violations.contains {
        $0.law == .unclassifiedSource && $0.location.file == "Sources/Core/Resources/data.json"
    })
    #expect(findingStatus(.forbiddenDependency, in: assessment) == .violated)
    #expect(findingStatus(.unclassifiedSource, in: assessment) == .violated)
    #expect(findingStatus(.forbiddenComment, in: assessment) == .unassessed(.sourceUnclassified))
}

@Test
func externalPackageLawsRejectDynamicManifestAndSourceComments() throws {
    let scratch = try externalPackageScratch()
    try writeExternalSource(
        externalManifest(targetName: "Core", targetKind: "target", languageModes: "")
            + "package.targets.append(.target(name: \"Hidden\"))\n",
        path: "Package.swift",
        scratch: scratch
    )
    try writeExternalSource("let value = 1 // hidden\n", path: "Sources/Core/Core.swift", scratch: scratch)
    let assessment = try LawScanner.scanExternalSwiftPackage(root: scratch.path)
    #expect(assessment.report.violations.contains { $0.law == .unclassifiedTarget })
    #expect(assessment.report.violations.contains { $0.law == .forbiddenComment })
    #expect(findingStatus(.reverseDependency, in: assessment) == .unassessed(.manifestUnclassified))
}

@Test
func externalPackageLawsDoNotTrustSwiftestBoundaryPathNames() throws {
    let scratch = try externalPackageScratch()
    try writeExternalSource(
        externalManifest(targetName: "SwiftestPlatform", targetKind: "target", languageModes: ""),
        path: "Package.swift",
        scratch: scratch
    )
    try writeExternalSource(
        "let value = unsafeBitCast(1, to: Int.self)\n",
        path: "Sources/SwiftestPlatform/ABIAdapter.swift",
        scratch: scratch
    )
    let assessment = try LawScanner.scanExternalSwiftPackage(root: scratch.path)
    #expect(assessment.report.violations.contains { $0.law == .unsafeOutsideBoundary })
    #expect(findingStatus(.unsafeOutsideBoundary, in: assessment) == .violated)
}

@Test
func externalPackageLawsDoNotPassVacuouslyWithoutADeclaredSourceTree() throws {
    let scratch = try externalPackageScratch()
    let assessment = try LawScanner.scanExternalSwiftPackage(root: scratch.path)
    #expect(assessment.report.violations.contains {
        $0.law == .unclassifiedTarget && $0.location.file == "Package.swift"
    })
    #expect(findingStatus(.forbiddenComment, in: assessment) == .unassessed(.manifestUnclassified))
    #expect(assessment.lawObservations.contains {
        $0.code == .forbiddenComment && $0.status == .failed
    })
}

@Test
func externalPackageLawsRejectUnknownRootFilesAndSymbolicLinks() throws {
    let scratch = try externalPackageScratch()
    try writeExternalSource(
        externalManifest(targetName: "Core", targetKind: "target", languageModes: ""),
        path: "Package.swift",
        scratch: scratch
    )
    try writeExternalSource("let value = 1\n", path: "Sources/Core/Core.swift", scratch: scratch)
    try writeExternalSource("unclassified\n", path: "unexpected.txt", scratch: scratch)
    let destination = try ArtifactPath.parse("Sources/Core/Core.swift")
    let link = try ArtifactPath.parse("Sources/Core/Linked.swift")
    try FileSystemBoundary.createSymbolicLink(
        relativePath: link,
        destination: destination,
        capability: scratch.issueWriteCapability()
    )
    let assessment = try LawScanner.scanExternalSwiftPackage(root: scratch.path)
    #expect(assessment.report.violations.contains {
        $0.law == .unclassifiedSource && $0.location.file == "unexpected.txt"
    })
    #expect(assessment.report.violations.contains {
        $0.law == .unreadableSource && $0.location.file == "Sources/Core/Linked.swift"
    })
    #expect(findingStatus(.forbiddenComment, in: assessment) == .unassessed(.sourceUnclassified))
}

@Test
func externalPackageLawsRejectUnknownManifestDependencyWithoutClaimingGraphClosure() throws {
    let scratch = try externalPackageScratch()
    let manifest = externalManifest(targetName: "Core", targetKind: "target", languageModes: "")
        .replacingOccurrences(
            of: "targets:",
            with: "dependencies: [.package(url: \"https://example.invalid/Unknown\", from: \"1.0.0\")],\n    targets:"
        )
    try writeExternalSource(manifest, path: "Package.swift", scratch: scratch)
    try writeExternalSource("let value = 1\n", path: "Sources/Core/Core.swift", scratch: scratch)
    let assessment = try LawScanner.scanExternalSwiftPackage(root: scratch.path)
    #expect(assessment.report.violations.contains { $0.law == .unclassifiedTarget })
    #expect(findingStatus(.forbiddenDependency, in: assessment) == .unassessed(.manifestUnclassified))
    #expect(assessment.lawObservations.contains {
        $0.code == .forbiddenDependency && $0.diagnostic?.code == .missingEvidence
    })
}

@Test
func externalXcodeLawAssessmentNeverPassesUninspectedLaws() {
    let assessment = TargetLawAssessment.unassessedExternalXcode()
    #expect(assessment.findings.count == LawCode.allCases.count)
    #expect(assessment.findings.allSatisfy { $0.status == .unassessed(.xcodeAssessmentUnavailable) })
    #expect(assessment.lawObservations.allSatisfy { $0.status == .failed })
}
