import Foundation
import SwiftestModel
import SwiftestPlatform
import Testing

@Test
func generatedSourceExclusionsMatchOnlyClosedRootNames() {
    for excluded in SourceExcludedDirectory.allCases {
        #expect(SourceExclusionPolicy.excludesDirectory(relativePath: excluded.rawValue))
        #expect(!SourceExclusionPolicy.excludesDirectory(relativePath: "Sources/" + excluded.rawValue))
    }
    #expect(!SourceExclusionPolicy.excludesDirectory(relativePath: "build"))
}

@Test
func pinnedAppleProcessReceivesOnlyClosedEnvironment() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-environment-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let output = try ProcessBoundary.runPinnedApple(
        executable: "/usr/bin/env",
        arguments: [],
        workingDirectory: scratch.path,
        scratch: scratch
    )
    let variables = output.standardOutput.split(separator: "\n").map { line in
        String(line.prefix { $0 != "=" })
    }
    #expect(Set(variables) == [
        "CLANG_MODULE_CACHE_PATH", "DEVELOPER_DIR", "HOME", "LANG", "LC_ALL",
        "PATH", "SWIFTPM_MODULECACHE_OVERRIDE", "TMPDIR",
    ])
    #expect(output.standardOutput.contains("DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer\n"))
    #expect(output.standardOutput.contains("HOME=" + scratch.path + "\n"))
    #expect(output.standardError.isEmpty)
}

@Test
func pinnedAppleProcessRejectsRedirectedModuleCache() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-cache-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let first = try ProcessBoundary.runPinnedApple(
        executable: "/usr/bin/true",
        arguments: [],
        workingDirectory: scratch.path,
        scratch: scratch
    )
    #expect(first.exitCode == 0)
    let cache = try ArtifactPath.parse("module-cache")
    let outside = try ArtifactPath.parse("redirected-cache")
    try FileSystemBoundary.remove(relativePath: cache, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.createDirectory(relativePath: outside, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.createSymbolicLink(
        relativePath: cache,
        destination: outside,
        capability: scratch.issueWriteCapability()
    )
    do {
        let output = try ProcessBoundary.runPinnedApple(
            executable: "/usr/bin/true",
            arguments: [],
            workingDirectory: scratch.path,
            scratch: scratch
        )
        Issue.record("redirected module cache was accepted")
        #expect(output.exitCode != 0)
    } catch let error {
        switch error {
        case .pathEscapesRoot, .createDirectory:
            break
        default:
            Issue.record("unexpected redirected cache failure")
        }
    }
}

@Test
func pinnedAppleProcessSeparatesLargeStandardErrorFromJSONStandardOutput() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-process-streams-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let output = try ProcessBoundary.runPinnedApple(
        executable: "/usr/bin/awk",
        arguments: [
            "BEGIN { print \"{\\\"ok\\\":true}\"; for (i = 0; i < 20000; i++) print \"warning\" > \"/dev/stderr\" }",
        ],
        workingDirectory: scratch.path,
        scratch: scratch
    )
    #expect(output.standardOutput == "{\"ok\":true}\n")
    #expect(output.standardError.utf8.count == 160000)
    #expect(output.exitCode == 0)
    #expect(try FileSystemBoundary.list(path: scratch.path).allSatisfy {
        !$0.hasPrefix("swiftest-stderr-")
    })
}

@Test
func failedProcessRetainsLengthDelimitedStandardErrorDiagnostic() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-process-exit-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    do {
        let output = try ProcessBoundary.runPinnedApple(
            executable: "/bin/sh",
            arguments: ["-c", "printf 'result\\n'; printf 'failure\\n' >&2; exit 17"],
            workingDirectory: scratch.path,
            scratch: scratch
        )
        Issue.record("nonzero process exit was accepted")
        #expect(output.exitCode != 0)
    } catch let error {
        guard case .processExit("/bin/sh", 17, let detail) = error else {
            Issue.record("unexpected process failure")
            return
        }
        #expect(detail.contains("stdout-bytes=7\nresult\n"))
        #expect(detail.contains("stderr-bytes=8\nfailure\n"))
    }
    #expect(try FileSystemBoundary.list(path: scratch.path).allSatisfy {
        !$0.hasPrefix("swiftest-stderr-")
    })
}

@Test
func sourceCopiesPreserveBytesAndRejectSymbolicLinks() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-copy-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let source = try ArtifactPath.parse("source.txt")
    let copied = try ArtifactPath.parse("copied.txt")
    let link = try ArtifactPath.parse("link.txt")
    let rejected = try ArtifactPath.parse("rejected.txt")
    let payload = Data("immutable input".utf8)
    try FileSystemBoundary.write(payload, relativePath: source, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.copyRegularFile(
        from: scratch.path + "/source.txt",
        relativePath: copied,
        capability: scratch.issueWriteCapability()
    )
    #expect(try FileSystemBoundary.read(root: scratch.path, relativePath: copied) == payload)
    #expect(try FileSystemBoundary.mode(path: scratch.path + "/source.txt")
        == FileSystemBoundary.mode(path: scratch.path + "/copied.txt"))
    try FileSystemBoundary.createSymbolicLink(
        relativePath: link,
        destination: source,
        capability: scratch.issueWriteCapability()
    )
    do {
        try FileSystemBoundary.copyRegularFile(
            from: scratch.path + "/link.txt",
            relativePath: rejected,
            capability: scratch.issueWriteCapability()
        )
        Issue.record("symbolic link was copied as source input")
    } catch let error {
        #expect(error == .read(scratch.path + "/link.txt"))
    }
    let sourceDirectory = try ArtifactPath.parse("source-directory")
    let sourceDirectoryFile = try ArtifactPath.parse("source-directory/file.txt")
    let sourceAlias = try ArtifactPath.parse("source-alias")
    let rejectedAliasCopy = try ArtifactPath.parse("rejected-alias-copy.txt")
    try FileSystemBoundary.createDirectory(
        relativePath: sourceDirectory,
        capability: scratch.issueWriteCapability()
    )
    try FileSystemBoundary.write(
        payload,
        relativePath: sourceDirectoryFile,
        capability: scratch.issueWriteCapability()
    )
    try FileSystemBoundary.createSymbolicLink(
        relativePath: sourceAlias,
        destination: sourceDirectory,
        capability: scratch.issueWriteCapability()
    )
    #expect(throws: PlatformError.read(scratch.path + "/source-alias/file.txt")) {
        try FileSystemBoundary.copyRegularFile(
            from: scratch.path + "/source-alias/file.txt",
            relativePath: rejectedAliasCopy,
            capability: scratch.issueWriteCapability()
        )
    }
    #expect(try FileSystemBoundary.list(path: scratch.path).contains("rejected-alias-copy.txt") == false)
}

@Test
func writeCapabilityRejectsSymlinkParentEscapes() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-capability-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let authorized = try ArtifactPath.parse("authorized")
    let outside = try ArtifactPath.parse("outside")
    let link = try ArtifactPath.parse("authorized/escape")
    let outsideData = try ArtifactPath.parse("outside/data.txt")
    let escapedData = try ArtifactPath.parse("escape/data.txt")
    let escapedDirectory = try ArtifactPath.parse("escape/new-directory")
    try FileSystemBoundary.createDirectory(relativePath: authorized, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.createDirectory(relativePath: outside, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.write(
        Data("untouched".utf8),
        relativePath: outsideData,
        capability: scratch.issueWriteCapability()
    )
    try FileSystemBoundary.createSymbolicLink(
        relativePath: link,
        destination: outside,
        capability: scratch.issueWriteCapability()
    )
    let restrictedRoot = scratch.path + "/authorized"

    do {
        try FileSystemBoundary.write(
            Data("escaped".utf8),
            relativePath: escapedData,
            capability: FileSystemAuthority.grant(root: restrictedRoot)
        )
        Issue.record("write crossed a symbolic-link boundary")
    } catch {
        #expect(error == .pathEscapesRoot("escape/data.txt"))
    }

    do {
        try FileSystemBoundary.createDirectory(
            relativePath: escapedDirectory,
            capability: FileSystemAuthority.grant(root: restrictedRoot)
        )
        Issue.record("directory creation crossed a symbolic-link boundary")
    } catch {
        #expect(error == .pathEscapesRoot("escape/new-directory"))
    }

    do {
        let data = try FileSystemBoundary.read(root: restrictedRoot, relativePath: escapedData)
        #expect(data.isEmpty)
    } catch {
        #expect(error == .pathEscapesRoot("escape/data.txt"))
    }

    do {
        try FileSystemBoundary.remove(
            relativePath: escapedData,
            capability: FileSystemAuthority.grant(root: restrictedRoot)
        )
        Issue.record("remove crossed a symbolic-link boundary")
    } catch {
        #expect(error == .pathEscapesRoot("escape/data.txt"))
    }

    #expect(try FileSystemBoundary.read(root: scratch.path, relativePath: outsideData) == Data("untouched".utf8))
}

@Test
func issuedCapabilityWritesToItsOpenedRootAfterThePathIsRebound() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-capability-root-rebind-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let original = try ArtifactPath.parse("original")
    let outside = try ArtifactPath.parse("outside")
    let movedPayload = try ArtifactPath.parse("moved/payload.txt")
    let outsideMarker = try ArtifactPath.parse("outside/marker.txt")
    let payload = Data("anchored".utf8)
    let marker = Data("outside unchanged".utf8)
    try FileSystemBoundary.createDirectory(relativePath: original, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.createDirectory(relativePath: outside, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.write(marker, relativePath: outsideMarker, capability: scratch.issueWriteCapability())
    let capability = try FileSystemAuthority.grant(root: scratch.path + "/original")
    let movedOutput = try ProcessBoundary.run(
        executable: "/bin/mv",
        arguments: [scratch.path + "/original", scratch.path + "/moved"],
        workingDirectory: scratch.path
    )
    #expect(movedOutput.exitCode == 0)
    try FileSystemBoundary.createSymbolicLink(
        relativePath: original,
        destination: outside,
        capability: scratch.issueWriteCapability()
    )
    try FileSystemBoundary.write(
        payload,
        relativePath: ArtifactPath.parse("payload.txt"),
        capability: capability
    )
    #expect(try FileSystemBoundary.read(root: scratch.path, relativePath: movedPayload) == payload)
    #expect(try FileSystemBoundary.read(root: scratch.path, relativePath: outsideMarker) == marker)
    #expect(try FileSystemBoundary.list(path: scratch.path + "/outside") == ["marker.txt"])
}

@Test
func capabilityRejectsAReboundNestedParentWithoutMutatingTheTarget() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-capability-parent-rebind-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let nested = try ArtifactPath.parse("root/nested")
    let outside = try ArtifactPath.parse("outside")
    let outsideMarker = try ArtifactPath.parse("outside/marker.txt")
    let marker = Data("outside unchanged".utf8)
    try FileSystemBoundary.createDirectory(relativePath: nested, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.createDirectory(relativePath: outside, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.write(marker, relativePath: outsideMarker, capability: scratch.issueWriteCapability())
    let capability = try FileSystemAuthority.grant(root: scratch.path + "/root")
    let movedOutput = try ProcessBoundary.run(
        executable: "/bin/mv",
        arguments: [scratch.path + "/root/nested", scratch.path + "/root/moved"],
        workingDirectory: scratch.path
    )
    #expect(movedOutput.exitCode == 0)
    try FileSystemBoundary.createSymbolicLink(
        relativePath: nested,
        destination: outside,
        capability: scratch.issueWriteCapability()
    )
    let attempted = try ArtifactPath.parse("nested/payload.txt")
    var writeFailure: PlatformError?
    do {
        try FileSystemBoundary.write(
            Data("escaped".utf8),
            relativePath: attempted,
            capability: capability
        )
    } catch let error {
        writeFailure = error
    }
    #expect(writeFailure == .pathEscapesRoot("nested/payload.txt"))
    #expect(try FileSystemBoundary.read(root: scratch.path, relativePath: outsideMarker) == marker)
    #expect(try FileSystemBoundary.list(path: scratch.path + "/outside") == ["marker.txt"])
    #expect(try FileSystemBoundary.list(path: scratch.path + "/root") == ["moved", "nested"])
    #expect(try FileSystemBoundary.list(path: scratch.path + "/root/moved").isEmpty)
}

@Test
func recursiveRemovalDoesNotFollowSymbolicLinksOutsideItsScope() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-capability-remove-link-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let nested = try ArtifactPath.parse("root/nested")
    let link = try ArtifactPath.parse("root/nested/escape")
    let outside = try ArtifactPath.parse("outside")
    let markerPath = try ArtifactPath.parse("outside/marker.txt")
    let marker = Data("retained".utf8)
    try FileSystemBoundary.createDirectory(relativePath: nested, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.createDirectory(relativePath: outside, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.write(marker, relativePath: markerPath, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.createSymbolicLink(
        relativePath: link,
        destination: outside,
        capability: scratch.issueWriteCapability()
    )
    try FileSystemBoundary.remove(
        relativePath: ArtifactPath.parse("nested"),
        capability: FileSystemAuthority.grant(root: scratch.path + "/root")
    )
    #expect(try FileSystemBoundary.list(path: scratch.path + "/root").isEmpty)
    #expect(try FileSystemBoundary.read(root: scratch.path, relativePath: markerPath) == marker)
}

@Test
func symbolicLinkCreationRejectsAnExistingAliasTarget() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-capability-link-target-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let target = try ArtifactPath.parse("target")
    let alias = try ArtifactPath.parse("alias")
    let outer = try ArtifactPath.parse("outer")
    try FileSystemBoundary.createDirectory(relativePath: target, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.createSymbolicLink(
        relativePath: alias,
        destination: target,
        capability: scratch.issueWriteCapability()
    )
    #expect(throws: PlatformError.pathEscapesRoot("outer")) {
        try FileSystemBoundary.createSymbolicLink(
            relativePath: outer,
            destination: alias,
            capability: scratch.issueWriteCapability()
        )
    }
    #expect(try FileSystemBoundary.list(path: scratch.path) == ["alias", "target"])
}
