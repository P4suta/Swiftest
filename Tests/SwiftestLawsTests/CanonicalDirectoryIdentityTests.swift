import SwiftestModel
import SwiftestPlatform
import Testing

@Test
func canonicalDirectoryIdentityRejectsSymlinkRootsAndDirectoryReplacement() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-root-identity-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let root = try ArtifactPath.parse("root")
    let replacement = try ArtifactPath.parse("replacement")
    let link = try ArtifactPath.parse("root-link")
    try FileSystemBoundary.createDirectory(relativePath: root, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.createDirectory(relativePath: replacement, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.createSymbolicLink(
        relativePath: link,
        destination: root,
        capability: scratch.issueWriteCapability()
    )
    let rootPath = scratch.path + "/root"
    let linkPath = scratch.path + "/root-link"
    let identity = try CanonicalPathBoundary.captureDirectoryIdentity(rootPath)
    try identity.verifyCurrentLocation()
    for candidate in [linkPath, linkPath + "/"] {
        do {
            let forged = try CanonicalPathBoundary.captureDirectoryIdentity(candidate)
            Issue.record("symbolic-link root was accepted")
            #expect(forged.canonicalPath.isEmpty)
        } catch let error {
            #expect(error == .invalidRoot(candidate))
        }
    }
    let retiredPath = scratch.path + "/retired"
    let firstMove = try ProcessBoundary.run(
        executable: "/bin/mv",
        arguments: [rootPath, retiredPath],
        workingDirectory: scratch.path
    )
    #expect(firstMove.exitCode == 0)
    let secondMove = try ProcessBoundary.run(
        executable: "/bin/mv",
        arguments: [scratch.path + "/replacement", rootPath],
        workingDirectory: scratch.path
    )
    #expect(secondMove.exitCode == 0)
    do {
        try identity.verifyCurrentLocation()
        Issue.record("replacement root retained the original identity")
    } catch let error {
        #expect(error == .invalidRoot(identity.canonicalPath))
    }
}
