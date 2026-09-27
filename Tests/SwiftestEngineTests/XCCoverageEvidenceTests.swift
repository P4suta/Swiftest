import Foundation
@testable import SwiftestEngine
import SwiftestModel
import SwiftestPlatform
import Testing

private struct CoverageEvidenceFixture {
    let root: String
    let first: String
    let second: String
    let third: String
    let product: String
    let alternateProduct: String

    init(scratch: borrowing ScratchDirectoryOwner) throws {
        self.root = try CanonicalPathBoundary.directory(scratch.path)
        self.first = root + "/Sources/First.swift"
        self.second = root + "/Sources/Second.swift"
        self.third = root + "/Sources/Third.swift"
        self.product = root + "/DerivedData/Build/Products/Debug/SmokeTests.xctest/Contents/MacOS/SmokeTests"
        self.alternateProduct = root + "/DerivedData/Build/Products/Debug/OtherTests.xctest/Contents/MacOS/OtherTests"
        for name in ["First", "Second", "Third"] {
            try FileSystemBoundary.write(
                Data("let \(name.lowercased()) = 1\n".utf8),
                relativePath: ArtifactPath.parse("Sources/\(name).swift"),
                capability: scratch.issueWriteCapability()
            )
        }
        try FileSystemBoundary.write(
            Data("binary".utf8),
            relativePath: ArtifactPath.parse("DerivedData/Build/Products/Debug/SmokeTests.xctest/Contents/MacOS/SmokeTests"),
            capability: scratch.issueWriteCapability()
        )
        try FileSystemBoundary.write(
            Data("other".utf8),
            relativePath: ArtifactPath.parse("DerivedData/Build/Products/Debug/OtherTests.xctest/Contents/MacOS/OtherTests"),
            capability: scratch.issueWriteCapability()
        )
    }

    var expectedSources: Set<String> {
        [first, second]
    }
}

private func coverageScratch() throws -> ScratchDirectoryOwner {
    try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-coverage-evidence-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
}

private func coverageEvidenceData(
    _ targets: [(name: String, product: String, paths: [String])]
) -> Data {
    let executable = targets.reduce(0) { $0 + $1.paths.count }
    let entries = targets.map { target in
        let files = target.paths.map { path in
            "{\"coveredLines\":0,\"executableLines\":1,\"lineCoverage\":0,\"name\":\"\(URL(fileURLWithPath: path).lastPathComponent)\",\"path\":\"\(path)\",\"functions\":[]}"
        }.joined(separator: ",")
        return "{\"coveredLines\":0,\"executableLines\":\(target.paths.count),\"lineCoverage\":0,\"name\":\"\(target.name)\",\"buildProductPath\":\"\(target.product)\",\"files\":[\(files)]}"
    }.joined(separator: ",")
    return Data("{\"coveredLines\":0,\"executableLines\":\(executable),\"lineCoverage\":0,\"targets\":[\(entries)]}".utf8)
}

private func decodedCoverage(
    name: String = "SmokeTests.xctest",
    product: String,
    paths: [String]
) throws -> XCCoverageReport {
    try XCCoverageReport.decode(coverageEvidenceData([(name, product, paths)]))
}

private func verifyCoverage(
    _ report: XCCoverageReport,
    fixture: CoverageEvidenceFixture
) throws {
    try report.verifyEvidence(
        expectedTargetName: "SmokeTests.xctest",
        expectedProductPath: fixture.product,
        expectedSourcePaths: fixture.expectedSources,
        repositoryRoot: fixture.root
    )
}

@Test
func xccovEvidenceAcceptsExactSourcesAndTmpAlias() throws {
    let scratch = try coverageScratch()
    let fixture = try CoverageEvidenceFixture(scratch: scratch)
    #expect(try FileSystemBoundary.entryKind(path: fixture.product) == .file)
    #expect(try CanonicalPathBoundary.existing(fixture.product) == fixture.product)
    let report = try decodedCoverage(product: fixture.product, paths: [fixture.first, fixture.second])
    try verifyCoverage(report, fixture: fixture)
    let aliased = try decodedCoverage(
        product: fixture.product.replacingOccurrences(of: "/private/tmp/", with: "/tmp/"),
        paths: [fixture.first, fixture.second].map {
            $0.replacingOccurrences(of: "/private/tmp/", with: "/tmp/")
        }
    )
    try verifyCoverage(aliased, fixture: fixture)
}

@Test
func xccovEvidenceRejectsWrongTargetProductAndAdditionalTarget() throws {
    let scratch = try coverageScratch()
    let fixture = try CoverageEvidenceFixture(scratch: scratch)
    let wrongTarget = try decodedCoverage(
        name: "OtherTests.xctest",
        product: fixture.product,
        paths: [fixture.first, fixture.second]
    )
    #expect(throws: XCCoverageError.targetNameMismatch("OtherTests.xctest")) {
        try verifyCoverage(wrongTarget, fixture: fixture)
    }
    let wrongProduct = try decodedCoverage(
        product: fixture.alternateProduct,
        paths: [fixture.first, fixture.second]
    )
    #expect(throws: XCCoverageError.productPathMismatch(fixture.alternateProduct)) {
        try verifyCoverage(wrongProduct, fixture: fixture)
    }
    let extraTarget = try XCCoverageReport.decode(coverageEvidenceData([
        ("SmokeTests.xctest", fixture.product, [fixture.first, fixture.second]),
        ("OtherTests.xctest", fixture.alternateProduct, [fixture.third]),
    ]))
    #expect(throws: XCCoverageError.targetCountMismatch(2)) {
        try verifyCoverage(extraTarget, fixture: fixture)
    }
}

@Test
func xccovEvidenceRejectsDuplicateExtraOmittedAndReplacedSources() throws {
    let scratch = try coverageScratch()
    let fixture = try CoverageEvidenceFixture(scratch: scratch)
    let duplicate = try decodedCoverage(
        product: fixture.product,
        paths: [fixture.first, fixture.second, fixture.first]
    )
    #expect(throws: XCCoverageError.duplicateSource(fixture.first)) {
        try verifyCoverage(duplicate, fixture: fixture)
    }
    let aliasedDuplicatePath = fixture.first.replacingOccurrences(of: "/private/tmp/", with: "/tmp/")
    let aliasedDuplicate = try decodedCoverage(
        product: fixture.product,
        paths: [fixture.first, fixture.second, aliasedDuplicatePath]
    )
    #expect(throws: XCCoverageError.duplicateSource(aliasedDuplicatePath)) {
        try verifyCoverage(aliasedDuplicate, fixture: fixture)
    }
    let extra = try decodedCoverage(
        product: fixture.product,
        paths: [fixture.first, fixture.second, fixture.third]
    )
    #expect(throws: XCCoverageError.unexpectedSource(fixture.third)) {
        try verifyCoverage(extra, fixture: fixture)
    }
    let omitted = try decodedCoverage(product: fixture.product, paths: [fixture.first])
    #expect(throws: XCCoverageError.missingSource(fixture.second)) {
        try verifyCoverage(omitted, fixture: fixture)
    }
    let replaced = try decodedCoverage(product: fixture.product, paths: [fixture.first, fixture.third])
    #expect(throws: XCCoverageError.unexpectedSource(fixture.third)) {
        try verifyCoverage(replaced, fixture: fixture)
    }
}

@Test
func xccovEvidenceRejectsExternalSymlinkAndNonregularSources() throws {
    let scratch = try coverageScratch()
    let fixture = try CoverageEvidenceFixture(scratch: scratch)
    let external = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-coverage-external-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    try FileSystemBoundary.write(
        Data("let external = 1\n".utf8),
        relativePath: ArtifactPath.parse("External.swift"),
        capability: external.issueWriteCapability()
    )
    let externalPath = external.path + "/External.swift"
    let outside = try decodedCoverage(product: fixture.product, paths: [fixture.first, externalPath])
    #expect(throws: XCCoverageError.sourceOutsideRepository(externalPath)) {
        try verifyCoverage(outside, fixture: fixture)
    }
    try FileSystemBoundary.createSymbolicLink(
        relativePath: ArtifactPath.parse("Sources/Alias.swift"),
        destination: ArtifactPath.parse("Sources/Second.swift"),
        capability: scratch.issueWriteCapability()
    )
    let alias = fixture.root + "/Sources/Alias.swift"
    let linked = try decodedCoverage(product: fixture.product, paths: [fixture.first, alias])
    #expect(throws: XCCoverageError.unsafePath(alias)) {
        try verifyCoverage(linked, fixture: fixture)
    }
    try FileSystemBoundary.createSymbolicLink(
        relativePath: ArtifactPath.parse("AliasSources"),
        destination: ArtifactPath.parse("Sources"),
        capability: scratch.issueWriteCapability()
    )
    let linkedDirectorySource = fixture.root + "/AliasSources/Second.swift"
    let linkedDirectory = try decodedCoverage(
        product: fixture.product,
        paths: [fixture.first, linkedDirectorySource]
    )
    #expect(throws: XCCoverageError.unsafePath(linkedDirectorySource)) {
        try verifyCoverage(linkedDirectory, fixture: fixture)
    }
    let directory = fixture.root + "/Sources"
    let nonregular = try decodedCoverage(product: fixture.product, paths: [fixture.first, directory])
    #expect(throws: XCCoverageError.unsafePath(directory)) {
        try verifyCoverage(nonregular, fixture: fixture)
    }
    try FileSystemBoundary.createSymbolicLink(
        relativePath: ArtifactPath.parse("LinkedProduct"),
        destination: ArtifactPath.parse("DerivedData/Build/Products/Debug/SmokeTests.xctest/Contents/MacOS/SmokeTests"),
        capability: scratch.issueWriteCapability()
    )
    let linkedProductPath = fixture.root + "/LinkedProduct"
    let linkedProduct = try decodedCoverage(
        product: linkedProductPath,
        paths: [fixture.first, fixture.second]
    )
    #expect(throws: XCCoverageError.unsafePath(linkedProductPath)) {
        try verifyCoverage(linkedProduct, fixture: fixture)
    }
}
