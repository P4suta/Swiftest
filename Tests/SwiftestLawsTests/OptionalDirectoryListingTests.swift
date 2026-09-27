import SwiftestModel
import SwiftestPlatform
import Testing

@Test
func optionalDirectoryListingDistinguishesAbsentFromUnreadable() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-optional-directory-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let root = try CanonicalPathBoundary.directory(scratch.path)
    #expect(try FileSystemBoundary.listIfPresent(path: root + "/missing") == .absent)
    let present = try ArtifactPath.parse("present")
    try FileSystemBoundary.createDirectory(
        relativePath: present,
        capability: scratch.issueWriteCapability()
    )
    #expect(try FileSystemBoundary.listIfPresent(path: root + "/present") == .entries([]))
    let link = try ArtifactPath.parse("link")
    try FileSystemBoundary.createSymbolicLink(
        relativePath: link,
        destination: present,
        capability: scratch.issueWriteCapability()
    )
    #expect(throws: PlatformError.read(root + "/link")) {
        let listing = try FileSystemBoundary.listIfPresent(path: root + "/link")
        #expect(listing == .absent)
    }
}
