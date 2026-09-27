import Foundation
import SwiftestModel
@testable import SwiftestPlatform
import Testing

@Test
func vnodeEventQueueDeliversAndClearsMutation() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-vnode-clear-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let path = try ArtifactPath.parse("Input.swift")
    try FileSystemBoundary.write(
        Data("let value = 1\n".utf8),
        relativePath: path,
        capability: scratch.issueWriteCapability()
    )
    let root = try CanonicalPathBoundary.directory(scratch.path)
    let file = root + "/Input.swift"
    let original = try FileSystemBoundary.mode(path: file)
    let changed: UInt16 = original.rawValue == 0o400 ? 0o600 : 0o400
    guard var queue = ABIAdapter.VnodeEventQueue() else {
        Issue.record("kqueue was unavailable")
        return
    }
    switch queue.register(WatchedInput(path: file, kind: .file)) {
    case .registered:
        break
    case .unavailable:
        Issue.record("vnode registration failed")
        return
    }
    let change = try ProcessBoundary.run(
        executable: "/bin/chmod",
        arguments: [String(changed, radix: 8), file],
        workingDirectory: nil
    )
    #expect(change.exitCode == 0)
    #expect(queue.nextEvent() == .mutation(file))
    #expect(queue.nextEvent() == .none)
}

@Test
func fileEventLeaseRejectsReversibleSourceReplacement() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-lease-file-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let path = try ArtifactPath.parse("Input.swift")
    let original = Data("let value = 1\n".utf8)
    try FileSystemBoundary.write(original, relativePath: path, capability: scratch.issueWriteCapability())
    let root = try CanonicalPathBoundary.directory(scratch.path)
    let lease = try FileEventLease(inputs: [
        WatchedInput(path: root, kind: .directory),
        WatchedInput(path: root + "/Input.swift", kind: .file),
    ])
    #expect(try FileSystemBoundary.read(root: root, relativePath: path) == original)
    #expect(try FileSystemBoundary.list(path: root) == ["Input.swift"])
    #expect(try lease.verifyUnchanged() == .eventFree)
    try FileSystemBoundary.write(
        Data("let value = 2\n".utf8),
        relativePath: path,
        capability: scratch.issueWriteCapability()
    )
    try FileSystemBoundary.write(original, relativePath: path, capability: scratch.issueWriteCapability())
    #expect(try FileSystemBoundary.read(root: scratch.path, relativePath: path) == original)
    do {
        let continuity = try lease.verifyUnchanged()
        Issue.record("reversible file write escaped event lease with \(continuity)")
    } catch let error {
        guard case .changedWhileWatched = error else {
            Issue.record("wrong file mutation diagnostic: \(error)")
            return
        }
    }
}

@Test
func fileEventLeaseRejectsReversibleModeChanges() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-lease-mode-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let path = try ArtifactPath.parse("Input.swift")
    try FileSystemBoundary.write(
        Data("let value = 1\n".utf8),
        relativePath: path,
        capability: scratch.issueWriteCapability()
    )
    let root = try CanonicalPathBoundary.directory(scratch.path)
    let file = root + "/Input.swift"
    let original = try FileSystemBoundary.mode(path: file)
    let changed: UInt16 = original.rawValue == 0o400 ? 0o600 : 0o400
    let lease = try FileEventLease(inputs: [WatchedInput(path: file, kind: .file)])
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
        let continuity = try lease.verifyUnchanged()
        Issue.record("reversible mode changes escaped the event lease with \(continuity)")
    } catch let error {
        guard case .changedWhileWatched = error else {
            Issue.record("wrong mode mutation diagnostic: \(error)")
            return
        }
        do {
            let continuity = try lease.verifyUnchanged()
            Issue.record("invalid event lease became valid after its event was consumed with \(continuity)")
        } catch let repeated {
            #expect(repeated == error)
        }
    }
}

@Test
func fileEventLeaseDoesNotCertifyAccessTimeStability() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-lease-access-time-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let path = try ArtifactPath.parse("Input.swift")
    let contents = Data("let value = 1\n".utf8)
    try FileSystemBoundary.write(contents, relativePath: path, capability: scratch.issueWriteCapability())
    let root = try CanonicalPathBoundary.directory(scratch.path)
    let file = root + "/Input.swift"
    let aged = try ProcessBoundary.run(
        executable: "/usr/bin/touch",
        arguments: ["-a", "-t", "202001010000", file],
        workingDirectory: nil
    )
    #expect(aged.exitCode == 0)
    let lease = try FileEventLease(inputs: [WatchedInput(path: file, kind: .file)])
    let before = try ProcessBoundary.run(
        executable: "/usr/bin/stat",
        arguments: ["-f", "%a", file],
        workingDirectory: nil
    )
    #expect(before.exitCode == 0)
    #expect(try FileSystemBoundary.read(path: file) == contents)
    let after = try ProcessBoundary.run(
        executable: "/usr/bin/stat",
        arguments: ["-f", "%a", file],
        workingDirectory: nil
    )
    #expect(after.exitCode == 0)
    #expect(after.standardOutput != before.standardOutput)
    let first = try lease.verifyUnchanged()
    let second = try lease.verifyUnchanged()
    #expect(first.joined(with: second) == second)
}

@Test
func fileEventLeaseRejectsReversibleDirectoryMembership() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-lease-directory-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let nested = try ArtifactPath.parse("Sources")
    let transient = try ArtifactPath.parse("Sources/Transient.swift")
    try FileSystemBoundary.createDirectory(relativePath: nested, capability: scratch.issueWriteCapability())
    let root = try CanonicalPathBoundary.directory(scratch.path)
    let lease = try FileEventLease(inputs: [
        WatchedInput(path: root, kind: .directory),
        WatchedInput(path: root + "/Sources", kind: .directory),
    ])
    #expect(try lease.verifyUnchanged() == .eventFree)
    try FileSystemBoundary.write(
        Data("let temporary = true\n".utf8),
        relativePath: transient,
        capability: scratch.issueWriteCapability()
    )
    try FileSystemBoundary.remove(relativePath: transient, capability: scratch.issueWriteCapability())
    #expect(try FileSystemBoundary.list(path: scratch.path + "/Sources").isEmpty)
    do {
        let continuity = try lease.verifyUnchanged()
        Issue.record("reversible directory edit escaped the event lease with \(continuity)")
    } catch let error {
        guard case .changedWhileWatched = error else {
            Issue.record("unexpected event lease failure")
            return
        }
    }
}

@Test
func fileEventLeaseRejectsSymbolicLinkAtRegistration() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-lease-link-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let original = try ArtifactPath.parse("Original.swift")
    let link = try ArtifactPath.parse("Linked.swift")
    try FileSystemBoundary.write(
        Data("let value = 1\n".utf8),
        relativePath: original,
        capability: scratch.issueWriteCapability()
    )
    try FileSystemBoundary.createSymbolicLink(
        relativePath: link,
        destination: original,
        capability: scratch.issueWriteCapability()
    )
    let root = try CanonicalPathBoundary.directory(scratch.path)
    do {
        let lease = try FileEventLease(inputs: [
            WatchedInput(path: root + "/Linked.swift", kind: .file),
        ])
        Issue.record("symbolic link was accepted as watched input")
        #expect(try lease.verifyUnchanged() == .eventFree)
    } catch let error {
        #expect(error == .watch(root + "/Linked.swift"))
    }
}
