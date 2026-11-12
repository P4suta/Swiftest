import Foundation
@testable import SwiftestLaws
import SwiftestModel
@testable import SwiftestPlatform
import Testing

private enum ProofVolumeFixtureFailure: Error {
    case expected
}

@Test
func proofVolumeKeepsMappedReadsEventFreeAndRejectsReversibleWrites() throws {
    let volume = try NoAccessTimeVolumeOwner()
    try volume.withRoot { (parent: String) throws -> Void in
        #expect(ABIAdapter.volumeAccessTimeUpdates(at: parent) == .disabled)
        let scratch = try ScratchDirectoryOwner(parent: parent, name: "mapped-input")
        let path = try ArtifactPath.parse("Proof.olean")
        let bytes = Data(repeating: 42, count: 65_536)
        try FileSystemBoundary.write(bytes, relativePath: path, capability: scratch.issueWriteCapability())
        let file = scratch.path + "/Proof.olean"
        let lease = try FileEventLease(inputs: [WatchedInput(path: file, kind: .file)])
        for _ in 0..<3 {
            let mapped = try Data(contentsOf: URL(fileURLWithPath: file), options: .alwaysMapped)
            #expect(mapped == bytes)
            try lease.requireEventFree()
        }
        let original = try FileSystemBoundary.mode(path: file)
        let changed: UInt16 = original.rawValue == 0o400 ? 0o600 : 0o400
        for mode in [changed, original.rawValue] {
            let result = try ProcessBoundary.run(
                executable: "/bin/chmod",
                arguments: [String(mode, radix: 8), file],
                workingDirectory: nil
            )
            #expect(result.exitCode == 0)
        }
        #expect(try FileSystemBoundary.mode(path: file) == original)
        do throws(PlatformError) {
            try lease.requireEventFree()
            Issue.record("reversible artifact mode change escaped the lease")
        } catch let error {
            guard case .changedWhileWatched = error else {
                Issue.record("wrong artifact mutation diagnostic: \(error)")
                return
            }
        }
    }
}

private func throwFromProofVolume() throws -> String {
    let volume = try NoAccessTimeVolumeOwner()
    var root = ""
    do {
        try volume.withRoot { (path: String) throws(ProofVolumeFixtureFailure) -> Void in
            root = path
            throw .expected
        }
    } catch ProofVolumeFixtureFailure.expected {
        return root
    }
    throw ProofVolumeFixtureFailure.expected
}

@Test
func proofVolumeDetachesAndRemovesItsScratchAfterFailure() throws {
    let root = try throwFromProofVolume()
    #expect(try FileSystemBoundary.listIfPresent(path: root) == .absent)
    let parent = URL(fileURLWithPath: root).deletingLastPathComponent().path
    #expect(try FileSystemBoundary.listIfPresent(path: parent) == .absent)
}

@Test
func proofVolumeRejectsAnOrdinaryDirectoryAsItsMountRoot() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-unmounted-proof-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    #expect(throws: PlatformError.invalidRoot(scratch.path)) {
        let identity = try NoAccessTimeVolumeOwner.verifiedRoot(scratch.path)
        Issue.record("ordinary directory was accepted at \(identity.canonicalPath)")
    }
}
