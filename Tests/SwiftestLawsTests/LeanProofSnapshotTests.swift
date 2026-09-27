import Foundation
@testable import SwiftestLaws
import SwiftestModel
@testable import SwiftestPlatform
import Testing

private let snapshotLakefile = "name = \"swiftest\"\n"
    + "version = \"0.1.0\"\n"
    + "defaultTargets = [\"SwiftestProofs\", \"swiftest-proof-oracle\"]\n"
    + "\n"
    + "[[lean_lib]]\n"
    + "name = \"SwiftestProofs\"\n"
    + "\n"
    + "[[lean_exe]]\n"
    + "name = \"swiftest-proof-oracle\"\n"
    + "root = \"SwiftestProofs.Oracle\"\n"

private let snapshotManifest = "{\"version\":\"1.2.0\",\"packagesDir\":\".lake/packages\","
    + "\"packages\":[],\"name\":\"swiftest\",\"lakeDir\":\".lake\",\"fixedToolchain\":false}"

private func proofFixture(_ variant: String) throws -> ScratchDirectoryOwner {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-proof-snapshot-" + variant + "-"
            + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let files = [
        "lakefile.toml": snapshotLakefile,
        "lean-toolchain": PinnedLeanToolchain.marker + "\n",
        "lake-manifest.json": snapshotManifest,
        "SwiftestProofs.lean": "import SwiftestProofs.Safe\n",
        "SwiftestProofs/Safe.lean": "def safe := true\n",
        "SwiftestProofs/Oracle.lean": "import SwiftestProofs.Safe\n",
    ]
    for (relative, content) in files {
        let path = try ArtifactPath.parse(relative)
        try FileSystemBoundary.write(
            Data(content.utf8),
            relativePath: path,
            capability: scratch.issueWriteCapability()
        )
    }
    return scratch
}

private func proofInputBytes(root: String) throws -> [String: Data] {
    let inventory = try LeanProofInputInventory.collect(root: root)
    return try Dictionary(uniqueKeysWithValues: inventory.allFiles.map { relative in
        (relative, try FileSystemBoundary.read(path: root + "/" + relative))
    })
}

@Test
func leanEventPhaseRetainsAttributePathWithoutMaskingOtherFailures() {
    guard let path = WatchedPath.validated("/private/tmp/SwiftestProofs.lean") else {
        Issue.record("valid proof path was rejected")
        return
    }
    for phase in LeanEventPhase.allCases {
        #expect(
            LeanEventContinuity.map(.attributeAmbiguous(path), at: phase)
                == .attributeAmbiguity(phase, path)
        )
        #expect(
            LeanEventContinuity.map(.eventGenerationOverflow, at: phase)
                == .platform(.eventGenerationOverflow)
        )
    }
}

@Test
func proofSnapshotCopiesOnlyAuditedLeanInputs() throws {
    let source = try proofFixture("copies")
    let unrelated = try ArtifactPath.parse("Unrelated.swift")
    try FileSystemBoundary.write(
        Data("let value = 1\n".utf8),
        relativePath: unrelated,
        capability: source.issueWriteCapability()
    )
    let snapshot = try LeanProofSnapshot(sourceRoot: source.path)
    try snapshot.verifyUnchanged()
    #expect(snapshot.proofModules == [
        "SwiftestProofs", "SwiftestProofs.Oracle", "SwiftestProofs.Safe",
    ])
    #expect(try FileSystemBoundary.list(path: snapshot.root) == [
        ".lake", "SwiftestProofs", "SwiftestProofs.lean", "lake-manifest.json", "lakefile.toml", "lean-toolchain",
    ])
    #expect(try FileSystemBoundary.read(path: snapshot.root + "/SwiftestProofs/Safe.lean")
        == Data("def safe := true\n".utf8))
}

@Test
func proofSnapshotBootstrapsMissingManifestWithoutWritingSource() throws {
    let source = try proofFixture("missing-manifest")
    let manifest = try ArtifactPath.parse("lake-manifest.json")
    try FileSystemBoundary.remove(
        relativePath: manifest,
        capability: source.issueWriteCapability()
    )
    let before = try FileSystemBoundary.list(path: source.path)
    let sourceBytes = try proofInputBytes(root: source.path)
    #expect(!before.contains("lake-manifest.json"))
    let snapshot = try LeanProofSnapshot(sourceRoot: source.path)
    try snapshot.verifyUnchanged()
    #expect(try FileSystemBoundary.list(path: source.path) == before)
    #expect(try proofInputBytes(root: source.path) == sourceBytes)
    #expect(try FileSystemBoundary.read(path: snapshot.root + "/lake-manifest.json")
        == LeanTrust.canonicalManifest)
    try LeanTrust.auditManifest(root: snapshot.root)
}

@Test
func proofSnapshotRetainsPresentManifestAndSourceBytes() throws {
    let source = try proofFixture("present-manifest")
    let sourceBytes = try proofInputBytes(root: source.path)
    let snapshot = try LeanProofSnapshot(sourceRoot: source.path)
    try snapshot.verifyUnchanged()
    #expect(try proofInputBytes(root: source.path) == sourceBytes)
    #expect(try FileSystemBoundary.read(path: snapshot.root + "/lake-manifest.json")
        == sourceBytes["lake-manifest.json"])
    try LeanTrust.auditManifest(root: snapshot.root)
}

@Test
func proofSnapshotRejectsMalformedPresentManifest() throws {
    let source = try proofFixture("malformed-manifest")
    let manifest = try ArtifactPath.parse("lake-manifest.json")
    try FileSystemBoundary.write(
        Data("{\"packages\":[],\"packages\":[]}".utf8),
        relativePath: manifest,
        capability: source.issueWriteCapability()
    )
    do {
        let snapshot = try LeanProofSnapshot(sourceRoot: source.path)
        Issue.record("malformed manifest reached Lake at \(snapshot.root)")
    } catch let error {
        guard case .trust(.lakeManifestCodec(.duplicateKey)) = error else {
            Issue.record("wrong malformed manifest diagnostic: \(error)")
            return
        }
    }
}

@Test
func proofSnapshotRejectsReversibleManifestInsertionAfterBootstrap() throws {
    let source = try proofFixture("manifest-insertion")
    let manifest = try ArtifactPath.parse("lake-manifest.json")
    try FileSystemBoundary.remove(
        relativePath: manifest,
        capability: source.issueWriteCapability()
    )
    let snapshot = try LeanProofSnapshot(sourceRoot: source.path)
    try FileSystemBoundary.write(
        LeanTrust.canonicalManifest,
        relativePath: manifest,
        capability: source.issueWriteCapability()
    )
    try FileSystemBoundary.remove(
        relativePath: manifest,
        capability: source.issueWriteCapability()
    )
    do {
        try snapshot.verifyUnchanged()
        Issue.record("reversible manifest insertion escaped source lease")
    } catch let error {
        guard case .platform(.changedWhileWatched) = error else {
            Issue.record("wrong manifest insertion diagnostic: \(error)")
            return
        }
    }
}

@Test
func proofSnapshotRejectsAmbiguousProofModuleNames() throws {
    let source = try proofFixture("ambiguous-module")
    let ambiguous = try ArtifactPath.parse("SwiftestProofs/Safe.Other.lean")
    try FileSystemBoundary.write(
        Data("def unused := true\n".utf8),
        relativePath: ambiguous,
        capability: source.issueWriteCapability()
    )
    #expect(throws: LeanProofSnapshotError.changed("proof-module:SwiftestProofs/Safe.Other.lean")) {
        let snapshot = try LeanProofSnapshot(sourceRoot: source.path)
        Issue.record("ambiguous proof module accepted at \(snapshot.root)")
    }
}

@Test
func proofSnapshotIncludesUnimportedProofModulesInFormalInventory() throws {
    let source = try proofFixture("unimported-module")
    let orphan = try ArtifactPath.parse("SwiftestProofs/Orphan.lean")
    try FileSystemBoundary.write(
        Data("theorem orphan : True := trivial\n".utf8),
        relativePath: orphan,
        capability: source.issueWriteCapability()
    )
    let snapshot = try LeanProofSnapshot(sourceRoot: source.path)
    #expect(snapshot.proofModules.contains("SwiftestProofs.Orphan"))
    #expect(snapshot.proofModules.contains("SwiftestProofs.Oracle"))
}

@Test
func proofSnapshotRejectsReversibleSourceAndSnapshotMutation() throws {
    let source = try proofFixture("source-mutation")
    let snapshot = try LeanProofSnapshot(sourceRoot: source.path)
    let safe = try ArtifactPath.parse("SwiftestProofs/Safe.lean")
    let original = Data("def safe := true\n".utf8)
    try FileSystemBoundary.write(
        Data("def safe := false\n".utf8),
        relativePath: safe,
        capability: source.issueWriteCapability()
    )
    try FileSystemBoundary.write(original, relativePath: safe, capability: source.issueWriteCapability())
    do {
        try snapshot.verifyUnchanged()
        Issue.record("reversible source change escaped proof snapshot")
    } catch let error {
        guard case .platform(.changedWhileWatched) = error else {
            Issue.record("wrong source change diagnostic: \(error)")
            return
        }
    }

    let independentSource = try proofFixture("snapshot-mutation")
    let independentSnapshot = try LeanProofSnapshot(sourceRoot: independentSource.path)
    let snapshotCapability = try FileSystemAuthority.grant(root: independentSnapshot.root)
    try FileSystemBoundary.write(Data("def safe := false\n".utf8), relativePath: safe, capability: snapshotCapability)
    try FileSystemBoundary.write(
        original,
        relativePath: safe,
        capability: try FileSystemAuthority.grant(root: independentSnapshot.root)
    )
    do {
        try independentSnapshot.verifyUnchanged()
        Issue.record("reversible snapshot change escaped proof snapshot")
    } catch let error {
        guard case .platform(.changedWhileWatched) = error else {
            Issue.record("wrong snapshot change diagnostic: \(error)")
            return
        }
    }
}

@Test
func proofSnapshotRejectsReversibleSourceModeChanges() throws {
    let source = try proofFixture("source-mode-mutation")
    let snapshot = try LeanProofSnapshot(sourceRoot: source.path)
    let file = source.path + "/SwiftestProofs/Safe.lean"
    let original = try FileSystemBoundary.mode(path: file)
    let changed: UInt16 = original.rawValue == 0o400 ? 0o600 : 0o400
    let change = try ProcessBoundary.run(
        executable: "/bin/chmod",
        arguments: [String(changed, radix: 8), file],
        workingDirectory: nil
    )
    #expect(change.exitCode == 0)
    let restore = try ProcessBoundary.run(
        executable: "/bin/chmod",
        arguments: [String(original.rawValue, radix: 8), file],
        workingDirectory: nil
    )
    #expect(restore.exitCode == 0)
    #expect(try FileSystemBoundary.mode(path: file) == original)
    do {
        try snapshot.verifyUnchanged()
        Issue.record("reversible source mode change escaped proof snapshot")
    } catch let error {
        guard case .platform(.changedWhileWatched) = error else {
            Issue.record("wrong mode change diagnostic: \(error)")
            return
        }
    }
}

@Test
func proofSnapshotRejectsClosedInputViolationsBeforeLake() throws {
    let source = try proofFixture("manifest")
    let manifest = try ArtifactPath.parse("lake-manifest.json")
    try FileSystemBoundary.write(
        Data(snapshotManifest.replacingOccurrences(of: "\"packages\":[]", with: "\"packages\":[{}]").utf8),
        relativePath: manifest,
        capability: source.issueWriteCapability()
    )
    do {
        let snapshot = try LeanProofSnapshot(sourceRoot: source.path)
        Issue.record("untrusted manifest reached Lake")
        try snapshot.verifyUnchanged()
    } catch let error {
        #expect(error == .trust(.lakeManifestMismatch))
    }

    let linkedSource = try proofFixture("symlink")
    let link = try ArtifactPath.parse("SwiftestProofs/Linked.lean")
    let destination = try ArtifactPath.parse("SwiftestProofs/Safe.lean")
    try FileSystemBoundary.createSymbolicLink(
        relativePath: link,
        destination: destination,
        capability: linkedSource.issueWriteCapability()
    )
    do {
        let snapshot = try LeanProofSnapshot(sourceRoot: linkedSource.path)
        Issue.record("symlinked proof reached Lake")
        try snapshot.verifyUnchanged()
    } catch let error {
        #expect(error == .trust(.unexpectedEntry("SwiftestProofs/Linked.lean")))
    }
}
