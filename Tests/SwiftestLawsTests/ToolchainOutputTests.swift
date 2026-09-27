@testable import SwiftestLaws
import SwiftestPlatform
import Testing

@Test
func pinnedToolchainAuditAcceptsDiagnosticPreambleButRejectsAmbiguousVersions() {
    let warning = "xcodebuild: warning: local cache unavailable\n"
    let swift = "swift-driver version: 1.168.6 Apple Swift version 6.4 (swiftlang-6.4.0)\n"
    let xcode = "Xcode 27.0\nBuild version 27A266a\n"
    #expect(ToolchainAudit.observation(
        component: "Swift",
        expected: "6.4",
        actual: warning + swift
    ).status == .matched)
    #expect(ToolchainAudit.observation(
        component: "Xcode",
        expected: "27.0",
        actual: warning + xcode
    ).status == .matched)
    #expect(ToolchainAudit.observation(
        component: "Swift",
        expected: "6.4",
        actual: swift + swift
    ).status == .mismatched)
    let streams = ProcessOutput(
        standardOutput: swift,
        standardError: warning + swift,
        exitCode: 0
    )
    #expect(ToolchainAudit.observation(
        component: "Swift",
        expected: "6.4",
        actual: ToolchainAudit.versionText(streams)
    ).status == .mismatched)
    let splitStreams = ProcessOutput(
        standardOutput: "Apple Swift version 6.4 (swiftlang-6.4.0)\nTarget: arm64-apple-macosx27.0.0\n",
        standardError: warning + "swift-driver version: 1.168.6 ",
        exitCode: 0
    )
    #expect(ToolchainAudit.observation(
        component: "Swift",
        expected: "6.4",
        actual: ToolchainAudit.versionText(splitStreams)
    ).status == .matched)
}
