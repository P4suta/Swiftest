import Foundation
import SwiftestModel
import SwiftestPlatform
import Testing

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
