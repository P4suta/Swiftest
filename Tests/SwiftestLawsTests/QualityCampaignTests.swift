import Foundation
import SwiftestModel
@testable import SwiftestPlatform
import Testing

private func qualityFixture() throws -> ScratchDirectoryOwner {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-quality-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let project = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path
    let source = try FileSystemBoundary.read(path: project + "/Scripts/quality")
    try FileSystemBoundary.write(
        source, relativePath: ArtifactPath.parse("Scripts/quality"), capability: scratch.issueWriteCapability()
    )
    for directory in ["Plugins", "Sources", "Tests", "Fixtures", "SwiftestProofs", ".githooks", ".github", "docs"] {
        try FileSystemBoundary.write(
            Data(), relativePath: ArtifactPath.parse(directory + "/probe"), capability: scratch.issueWriteCapability()
        )
    }
    for file in ["Package.swift", "SwiftestProofs.lean", "lakefile.toml", "lean-toolchain", ".gitignore"] {
        try FileSystemBoundary.write(
            Data(), relativePath: ArtifactPath.parse(file), capability: scratch.issueWriteCapability()
        )
    }
    let swift = "#!/bin/sh\nprintf 'swift %s\\n' \"$*\" >>\"$QUALITY_TRACE\"\n"
    try FileSystemBoundary.write(
        Data(swift.utf8), relativePath: ArtifactPath.parse("bin/swift"), capability: scratch.issueWriteCapability()
    )
    let script = """
    #!/bin/sh
    name=${0##*/}
    printf '%s%s\\n' "$name" "${*:+ $*}" >>"$QUALITY_TRACE"
    if test "${FAIL_PHASE:-}" = "$name"; then exit 19; fi
    if test "${CHANGE_PHASE:-}" = "$name"; then printf 'changed\\n' >Sources/probe; fi
    """
    for name in ["platform-check", "compile-fail", "mutate-laws", "formal-check", "dogfood"] {
        try FileSystemBoundary.write(
            Data(script.utf8), relativePath: ArtifactPath.parse("Scripts/" + name), capability: scratch.issueWriteCapability()
        )
    }
    let prepared = try ProcessBoundary.run(
        executable: "/bin/chmod", arguments: ["-R", "+x", scratch.path], workingDirectory: nil
    )
    #expect(prepared.exitCode == 0)
    return scratch
}

private func runQuality(
    root: String, arguments: [String] = [], environment: [String] = []
) throws -> Int32 {
    do {
        let output = try ProcessBoundary.run(
        executable: "/usr/bin/env",
        arguments: ["PATH=" + root + "/bin:/usr/bin:/bin", "QUALITY_TRACE=" + root + "/trace"]
            + environment + ["/bin/sh", root + "/Scripts/quality"] + arguments,
        workingDirectory: root
        )
        return output.exitCode
    } catch PlatformError.processExit(_, let code, _) {
        return code
    }
}

@Test
func qualityPhasesPartitionTheCompleteCampaignWithoutDroppingCommands() throws {
    let whole = try qualityFixture()
    let complete = try runQuality(root: whole.path)
    #expect(complete == 0)
    let expected = """
    swift build --disable-sandbox --disable-index-store -j 4
    platform-check
    swift test --disable-sandbox --disable-index-store -j 4
    swift run --disable-sandbox --disable-index-store -j 4 swiftest laws . --formal
    compile-fail
    mutate-laws --phase mutations
    mutate-laws --phase proof-toolchain
    formal-check
    dogfood

    """
    let wholeTrace = try FileSystemBoundary.read(path: whole.path + "/trace")
    #expect(wholeTrace == Data(expected.utf8))
    let shards = try qualityFixture()
    for phase in ["source", "mutations", "proof-toolchain", "formal", "dogfood"] {
        let result = try runQuality(root: shards.path, arguments: ["--phase", phase])
        #expect(result == 0)
    }
    #expect(try FileSystemBoundary.read(path: shards.path + "/trace") == wholeTrace)
}

@Test
func qualityRejectsUnknownPhasesBeforeExecutingCommands() throws {
    let fixture = try qualityFixture()
    let result = try runQuality(root: fixture.path, arguments: ["--phase", "unknown"])
    #expect(result == 2)
    let entries = try FileSystemBoundary.list(path: fixture.path)
    #expect(!entries.contains("trace"))
}

@Test
func qualityPreservesPhaseFailureAndChecksSourceIntegrity() throws {
    let fixture = try qualityFixture()
    let failed = try runQuality(
        root: fixture.path, arguments: ["--phase", "formal"], environment: ["FAIL_PHASE=formal-check"]
    )
    #expect(failed == 19)
    #expect(try FileSystemBoundary.read(path: fixture.path + "/trace") == Data("formal-check\n".utf8))
    let changed = try runQuality(
        root: fixture.path, arguments: ["--phase", "dogfood"], environment: ["CHANGE_PHASE=dogfood"]
    )
    #expect(changed != 0)
}
