import Foundation
import SwiftestModel
import SwiftestPlatform
import Testing

@Test
func exclusiveOutputWritesOneNewFileAndRejectsReuse() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-exclusive-new-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let root = try CanonicalPathBoundary.directory(scratch.path)
    let outputPath = root + "/report.json"
    let owner = try ExclusiveOutputOwner(absolutePath: outputPath)
    try owner.write(Data("first".utf8))
    #expect(try FileSystemBoundary.read(path: outputPath) == Data("first".utf8))
    do {
        let duplicate = try ExclusiveOutputOwner(absolutePath: outputPath)
        try duplicate.write(Data("second".utf8))
        Issue.record("reused an existing report destination")
    } catch let error {
        #expect(error == .outputExists(outputPath))
    }
    #expect(try FileSystemBoundary.read(path: outputPath) == Data("first".utf8))
}

@Test
func exclusiveOutputRejectsCreationRaceWithoutOverwriting() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-exclusive-race-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let relativePath = try ArtifactPath.parse("report.json")
    let root = try CanonicalPathBoundary.directory(scratch.path)
    let outputPath = root + "/report.json"
    let owner = try ExclusiveOutputOwner(absolutePath: outputPath)
    try FileSystemBoundary.write(
        Data("racer".utf8),
        relativePath: relativePath,
        capability: scratch.issueWriteCapability()
    )
    do {
        try owner.write(Data("report".utf8))
        Issue.record("overwrote a report destination created after preflight")
    } catch let error {
        #expect(error == .outputExists(outputPath))
    }
    #expect(try FileSystemBoundary.read(path: outputPath) == Data("racer".utf8))
}

@Test
func exclusiveOutputRejectsSymbolicLinkParentsAndLeavesTargetUntouched() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-exclusive-link-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let real = try ArtifactPath.parse("real")
    let alias = try ArtifactPath.parse("alias")
    let root = try CanonicalPathBoundary.directory(scratch.path)
    try FileSystemBoundary.createDirectory(relativePath: real, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.createSymbolicLink(
        relativePath: alias,
        destination: real,
        capability: scratch.issueWriteCapability()
    )
    do {
        let owner = try ExclusiveOutputOwner(absolutePath: root + "/alias/report.json")
        try owner.write(Data("unexpected".utf8))
        Issue.record("followed a symbolic-link parent")
    } catch let error {
        #expect(error == .invalidOutput(root + "/alias"))
    }
    #expect(!((try FileSystemBoundary.list(path: root + "/real")).contains("report.json")))
}

@Test
func exclusiveOutputRejectsExistingSymbolicLinkLeaf() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-exclusive-leaf-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let target = try ArtifactPath.parse("target.json")
    let link = try ArtifactPath.parse("report.json")
    let root = try CanonicalPathBoundary.directory(scratch.path)
    try FileSystemBoundary.write(Data("target".utf8), relativePath: target, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.createSymbolicLink(
        relativePath: link,
        destination: target,
        capability: scratch.issueWriteCapability()
    )
    do {
        let owner = try ExclusiveOutputOwner(absolutePath: root + "/report.json")
        try owner.write(Data("report".utf8))
        Issue.record("followed an existing output link")
    } catch let error {
        #expect(error == .outputExists(root + "/report.json"))
    }
    #expect(try FileSystemBoundary.read(path: root + "/target.json") == Data("target".utf8))
}

@Test
func exclusiveOutputRejectsRelativePaths() {
    for path in [
        "report.json",
        "/private/tmp/../report.json",
        "/private/tmp/./report.json",
        "/private/tmp//report.json",
        "/private/tmp/re\0port.json",
    ] {
        do {
            let owner = try ExclusiveOutputOwner(absolutePath: path)
            try owner.write(Data("unexpected".utf8))
            Issue.record("accepted an ambiguous report path")
        } catch let error {
            #expect(error == .invalidOutput(path))
        }
    }
}
