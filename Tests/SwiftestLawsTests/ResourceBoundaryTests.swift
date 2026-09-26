import Foundation
import SwiftestModel
import SwiftestPlatform
import Testing

@Test
func generatedSourceExclusionsMatchOnlyClosedRootNames() {
    #expect(SourceExclusionPolicy.excludesDirectory(relativePath: "dist"))
    #expect(SourceExclusionPolicy.excludesDirectory(relativePath: ".build"))
    #expect(!SourceExclusionPolicy.excludesDirectory(relativePath: "Sources/dist"))
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
