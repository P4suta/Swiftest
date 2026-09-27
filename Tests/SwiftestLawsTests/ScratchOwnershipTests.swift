import Foundation
import SwiftestModel
import SwiftestPlatform
import Testing

private enum ScratchAttempt: Sendable, Equatable {
    case rejected
    case unexpectedlyAcquired
    case wrongFailure
}

@Test
func scratchOwnerCapabilityKeepsIdentityAcrossPrivateTmpAndTmpAliases() throws {
    let owned = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-scratch-alias-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let alias = owned.path.replacingOccurrences(of: "/private/tmp/", with: "/tmp/")
    let canonicalOwned = try CanonicalPathBoundary.existing(owned.path)
    let canonicalAlias = try CanonicalPathBoundary.existing(alias)
    #expect(canonicalOwned == canonicalAlias)
    let marker = try ArtifactPath.parse("marker.txt")
    let payload = Data("same owned directory".utf8)
    try FileSystemBoundary.write(
        payload,
        relativePath: marker,
        capability: owned.issueVerifiedWriteCapability()
    )
    #expect(try FileSystemBoundary.read(root: owned.path, relativePath: marker) == payload)
    #expect(try FileSystemBoundary.read(root: alias, relativePath: marker) == payload)
    try owned.verifyOwnership()
}

@Test
func scratchOwnerRejectsExistingDirectoryWithoutChangingItsContents() throws {
    let parent = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-scratch-existing-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let existing = try ArtifactPath.parse("existing")
    let marker = try ArtifactPath.parse("existing/marker.txt")
    let payload = Data("original bytes".utf8)
    try FileSystemBoundary.createDirectory(relativePath: existing, capability: parent.issueWriteCapability())
    try FileSystemBoundary.write(payload, relativePath: marker, capability: parent.issueWriteCapability())
    let existingPath = parent.path + "/existing"
    do {
        let duplicate = try ScratchDirectoryOwner(parent: parent.path, name: "existing")
        try duplicate.verifyOwnership()
        Issue.record("existing scratch directory was acquired")
    } catch let error {
        switch error {
        case .createDirectory:
            break
        default:
            Issue.record("existing scratch directory had the wrong failure: \(error)")
        }
    }
    #expect(try FileSystemBoundary.read(root: parent.path, relativePath: marker) == payload)
    #expect(try FileSystemBoundary.list(path: existingPath) == ["marker.txt"])
}

@Test
func scratchOwnerRejectsConcurrentAcquisitionWhileTheDirectoryIsOwned() async throws {
    let parent = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-scratch-contention-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let owned = try ScratchDirectoryOwner(parent: parent.path, name: "contended")
    let parentPath = parent.path
    let first = TaskOwner<ScratchAttempt> {
        do {
            let duplicate = try ScratchDirectoryOwner(parent: parentPath, name: "contended")
            try duplicate.verifyOwnership()
            return .unexpectedlyAcquired
        } catch let error as PlatformError {
            switch error {
            case .createDirectory:
                return .rejected
            default:
                return .wrongFailure
            }
        } catch {
            return .wrongFailure
        }
    }
    let second = TaskOwner<ScratchAttempt> {
        do {
            let duplicate = try ScratchDirectoryOwner(parent: parentPath, name: "contended")
            try duplicate.verifyOwnership()
            return .unexpectedlyAcquired
        } catch let error as PlatformError {
            switch error {
            case .createDirectory:
                return .rejected
            default:
                return .wrongFailure
            }
        } catch {
            return .wrongFailure
        }
    }
    #expect(await first.value() == .rejected)
    #expect(await second.value() == .rejected)
    try owned.verifyOwnership()
    #expect(try FileSystemBoundary.list(path: parentPath) == ["contended"])
}

@Test
func scratchOwnerDetectsAReplacedDirectoryBeforeCleanup() throws {
    let parent = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-scratch-identity-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let owned = try ScratchDirectoryOwner(parent: parent.path, name: "owned")
    let moved = parent.path + "/moved"
    let movedOutput = try ProcessBoundary.run(
        executable: "/bin/mv",
        arguments: [owned.path, moved],
        workingDirectory: parent.path
    )
    #expect(movedOutput.exitCode == 0)
    try FileSystemBoundary.createSymbolicLink(
        relativePath: ArtifactPath.parse("owned"),
        destination: ArtifactPath.parse("moved"),
        capability: parent.issueWriteCapability()
    )
    #expect(throws: PlatformError.scratchOwnershipLost(owned.path)) {
        try owned.verifyOwnership()
    }
    #expect(throws: PlatformError.scratchOwnershipLost(owned.path)) {
        let capability = try owned.issueVerifiedWriteCapability()
        try FileSystemBoundary.write(
            Data("unexpected".utf8),
            relativePath: ArtifactPath.parse("unrelated.txt"),
            capability: capability
        )
    }
    #expect(try FileSystemBoundary.list(path: moved).isEmpty)
    try FileSystemBoundary.remove(
        relativePath: ArtifactPath.parse("owned"),
        capability: parent.issueWriteCapability()
    )
    let restoredOutput = try ProcessBoundary.run(
        executable: "/bin/mv",
        arguments: [moved, owned.path],
        workingDirectory: parent.path
    )
    #expect(restoredOutput.exitCode == 0)
    try owned.verifyOwnership()
    #expect(try FileSystemBoundary.list(path: parent.path) == ["owned"])
}

@Test
func issuedScratchCapabilityRemainsBoundWhileItsNameIsTemporarilyReplaced() throws {
    let parent = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-scratch-issued-rebind-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let owned = try ScratchDirectoryOwner(parent: parent.path, name: "owned")
    let replacement = try ArtifactPath.parse("replacement")
    let name = try ArtifactPath.parse("owned")
    let marker = try ArtifactPath.parse("marker.txt")
    let payload = Data("owned inode".utf8)
    try FileSystemBoundary.createDirectory(relativePath: replacement, capability: parent.issueWriteCapability())
    let capability = try owned.issueVerifiedWriteCapability()
    let movedOutput = try ProcessBoundary.run(
        executable: "/bin/mv",
        arguments: [owned.path, parent.path + "/moved"],
        workingDirectory: parent.path
    )
    #expect(movedOutput.exitCode == 0)
    try FileSystemBoundary.createSymbolicLink(
        relativePath: name,
        destination: replacement,
        capability: parent.issueWriteCapability()
    )
    var writeFailure: PlatformError?
    do {
        try FileSystemBoundary.write(payload, relativePath: marker, capability: capability)
    } catch let error {
        writeFailure = error
    }
    try FileSystemBoundary.remove(relativePath: name, capability: parent.issueWriteCapability())
    let restoredOutput = try ProcessBoundary.run(
        executable: "/bin/mv",
        arguments: [parent.path + "/moved", owned.path],
        workingDirectory: parent.path
    )
    #expect(restoredOutput.exitCode == 0)
    #expect(writeFailure == nil)
    #expect(try FileSystemBoundary.read(root: parent.path, relativePath: ArtifactPath.parse("owned/marker.txt")) == payload)
    #expect(try FileSystemBoundary.list(path: parent.path + "/replacement").isEmpty)
    try owned.verifyOwnership()
}

@Test
func scratchOwnerRejectsAmbiguousNamesAndParents() throws {
    let parent = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-scratch-name-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    for name in ["", ".", "..", "nested/child", "nul\0byte"] {
        #expect(throws: PlatformError.pathEscapesRoot(name)) {
            let invalid = try ScratchDirectoryOwner(parent: parent.path, name: name)
            try invalid.verifyOwnership()
        }
    }
    for invalidParent in ["relative", "/private/tmp/..", "/private/tmp//nested"] {
        #expect(throws: PlatformError.invalidRoot(invalidParent)) {
            let invalid = try ScratchDirectoryOwner(parent: invalidParent, name: "scratch")
            try invalid.verifyOwnership()
        }
    }
    #expect(try FileSystemBoundary.list(path: parent.path).isEmpty)
}
