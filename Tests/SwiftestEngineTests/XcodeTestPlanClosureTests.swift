import Foundation
@testable import SwiftestEngine
import SwiftestModel
import SwiftestPlatform
import Testing

private let minimalTestPlan = """
{"configurations":[{"id":"00000000-0000-0000-0000-000000000001","name":"Default Configuration","options":{}}],"defaultOptions":{},"testTargets":[{"target":{"containerPath":"container:Smoke.xcodeproj","identifier":"A00000000000000000000005","name":"SmokeTests"}}],"version":1}
"""

private let minimalPlanScheme = """
<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
    <BuildAction parallelizeBuildables="NO" buildImplicitDependencies="NO">
        <BuildActionEntries>
            <BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="NO">
                <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="A00000000000000000000005" BuildableName="SmokeTests.xctest" BlueprintName="SmokeTests" ReferencedContainer="container:Smoke.xcodeproj"/>
            </BuildActionEntry>
        </BuildActionEntries>
    </BuildAction>
    <TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="NO">
        <TestPlans><TestPlanReference reference="container:Smoke.xctestplan" default="YES"/></TestPlans>
    </TestAction>
</Scheme>
"""

@Test
func xcodePlanAcceptsObservedSingleConfigurationAndTarget() throws {
    #expect(try XcodeTestPlanClosure.decode(Data(minimalTestPlan.utf8)).targets.map(\.project)
        == ["Smoke.xcodeproj"])
    #expect(try XcodeSchemeClosure.inspect(Data(minimalPlanScheme.utf8)) == ["Smoke.xcodeproj"])
}

@Test
func xcodePlanRejectsUnknownOrAmbiguousConfiguration() {
    for plan in [
        minimalTestPlan.replacingOccurrences(of: "\"version\":1", with: "\"version\":2"),
        minimalTestPlan.replacingOccurrences(of: "\"defaultOptions\":{}", with: "\"defaultOptions\":{\"skip\":true}"),
        minimalTestPlan.replacingOccurrences(of: "\"options\":{}", with: "\"options\":{\"skip\":true}"),
        minimalTestPlan.replacingOccurrences(of: "\"version\":1", with: "\"version\":1,\"unknown\":0"),
        minimalTestPlan.replacingOccurrences(of: "\"configurations\":[", with: "\"configurations\":[] ,\"unused\":["),
        minimalTestPlan.replacingOccurrences(of: "\"version\":1", with: "\"version\":1,\"version\":1"),
    ] {
        #expect(throws: XcodeInputClosureError.self) {
            let inventory = try XcodeTestPlanClosure.decode(Data(plan.utf8))
            #expect(inventory.targets.isEmpty)
        }
    }
}

@Test
func xcodePlanRejectsDynamicExternalAndDuplicateTargets() {
    for reference in [
        "container:../External.xcodeproj",
        "container:/private/tmp/External.xcodeproj",
        "container:$(ROOT)/External.xcodeproj",
        "absolute:/private/tmp/External.xcodeproj",
    ] {
        let plan = minimalTestPlan.replacingOccurrences(
            of: "container:Smoke.xcodeproj",
            with: reference
        )
        #expect(throws: XcodeInputClosureError.self) {
            let inventory = try XcodeTestPlanClosure.decode(Data(plan.utf8))
            #expect(inventory.targets.isEmpty)
        }
    }
    let duplicate = minimalTestPlan.replacingOccurrences(
        of: "}],\"version\":1",
        with: "},{\"target\":{\"containerPath\":\"container:Smoke.xcodeproj\",\"identifier\":\"A00000000000000000000005\",\"name\":\"SmokeTests\"}}],\"version\":1"
    )
    #expect(throws: XcodeInputClosureError.invalidTestPlan("target")) {
        let inventory = try XcodeTestPlanClosure.decode(Data(duplicate.utf8))
        #expect(inventory.targets.isEmpty)
    }
}

@Test
func xcodeSchemeRejectsAmbiguousOrDynamicPlans() {
    let both = minimalPlanScheme.replacingOccurrences(
        of: "</TestAction>",
        with: "<Testables><TestableReference skipped=\"NO\"><BuildableReference BuildableIdentifier=\"primary\" BlueprintIdentifier=\"A00000000000000000000005\" BuildableName=\"SmokeTests.xctest\" BlueprintName=\"SmokeTests\" ReferencedContainer=\"container:Smoke.xcodeproj\"/></TestableReference></Testables></TestAction>"
    )
    #expect(throws: XcodeInputClosureError.invalidScheme) {
        let references = try XcodeSchemeClosure.inspect(Data(both.utf8))
        #expect(references.isEmpty)
    }
    let external = minimalPlanScheme.replacingOccurrences(
        of: "container:Smoke.xctestplan",
        with: "container:../External.xctestplan"
    )
    #expect(throws: XcodeInputClosureError.self) {
        let references = try XcodeSchemeClosure.inspect(Data(external.utf8))
        #expect(references.isEmpty)
    }
    let disabled = minimalPlanScheme.replacingOccurrences(of: "default=\"YES\"", with: "default=\"NO\"")
    #expect(throws: XcodeInputClosureError.invalidScheme) {
        let references = try XcodeSchemeClosure.inspect(Data(disabled.utf8))
        #expect(references.isEmpty)
    }
}

@Test
func xcodeSchemeRejectsUnmodeledExecutionSettings() {
    for (old, new) in [
        ("parallelizeBuildables=\"NO\"", "parallelizeBuildables=\"YES\""),
        ("buildImplicitDependencies=\"NO\"", "buildImplicitDependencies=\"YES\""),
        ("buildForRunning=\"NO\"", "buildForRunning=\"YES\""),
        ("shouldUseLaunchSchemeArgsEnv=\"NO\"", "shouldUseLaunchSchemeArgsEnv=\"YES\""),
        ("<TestAction buildConfiguration=\"Debug\"", "<TestAction enableThreadSanitizer=\"YES\" buildConfiguration=\"Debug\""),
    ] {
        let scheme = minimalPlanScheme.replacingOccurrences(of: old, with: new)
        #expect(throws: XcodeInputClosureError.self) {
            let references = try XcodeSchemeClosure.inspect(Data(scheme.utf8))
            #expect(references.isEmpty)
        }
    }
}

@Test
func xcodeSchemeBindsPlanTargetsAndRejectsUnreadableUserSchemes() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-scheme-closure-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let root = try CanonicalPathBoundary.directory(scratch.path)
    let projectPath = try ArtifactPath.parse("Smoke.xcodeproj")
    let schemePath = try ArtifactPath.parse("Smoke.xcodeproj/xcshareddata/xcschemes/Smoke.xcscheme")
    let planPath = try ArtifactPath.parse("Smoke.xctestplan")
    let primarySource = try ArtifactPath.parse("Tests/SmokeTests.swift")
    let substitutedSource = try ArtifactPath.parse("Tests/Substituted.swift")
    try FileSystemBoundary.createDirectory(relativePath: projectPath, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.write(
        Data("import XCTest\n".utf8),
        relativePath: primarySource,
        capability: scratch.issueWriteCapability()
    )
    try FileSystemBoundary.write(
        Data("import XCTest\n".utf8),
        relativePath: substitutedSource,
        capability: scratch.issueWriteCapability()
    )
    try FileSystemBoundary.write(
        Data(minimalPlanScheme.utf8),
        relativePath: schemePath,
        capability: scratch.issueWriteCapability()
    )
    try FileSystemBoundary.write(
        Data(minimalTestPlan.utf8),
        relativePath: planPath,
        capability: scratch.issueWriteCapability()
    )
    let container = try XcodeContainer.project(root + "/Smoke.xcodeproj")
    let project = XcodeVerifiedProject(
        path: container.path,
        targetIdentifiers: ["A00000000000000000000005", "A00000000000000000000006"],
        sourcePathsByTarget: [
            "A00000000000000000000005": [root + "/Tests/SmokeTests.swift"],
            "A00000000000000000000006": [root + "/Tests/Substituted.swift"],
        ]
    )
    let valid = try XcodeSchemeClosure.verify(
        scheme: "Smoke",
        container: container,
        projects: [project],
        repositoryRoot: root
    )
    #expect(valid.planName == "Smoke")
    #expect(valid.compiledSources.paths == [root + "/Tests/SmokeTests.swift"])
    let substituted = minimalPlanScheme.replacingOccurrences(
        of: "BlueprintIdentifier=\"A00000000000000000000005\"",
        with: "BlueprintIdentifier=\"A00000000000000000000006\""
    )
    try FileSystemBoundary.write(
        Data(substituted.utf8),
        relativePath: schemePath,
        capability: scratch.issueWriteCapability()
    )
    #expect(throws: XcodeInputClosureError.invalidTestPlan("scheme-build-target")) {
        let plan = try XcodeSchemeClosure.verify(
            scheme: "Smoke",
            container: container,
            projects: [project],
            repositoryRoot: root
        )
        #expect(plan.targets.isEmpty)
    }
    try FileSystemBoundary.write(
        Data(minimalPlanScheme.utf8),
        relativePath: schemePath,
        capability: scratch.issueWriteCapability()
    )
    let userDirectory = try ArtifactPath.parse("Smoke.xcodeproj/xcuserdata")
    try FileSystemBoundary.createSymbolicLink(
        relativePath: userDirectory,
        destination: projectPath,
        capability: scratch.issueWriteCapability()
    )
    #expect(throws: XcodeInputClosureError.platform(.read(container.path + "/xcuserdata"))) {
        let plan = try XcodeSchemeClosure.verify(
            scheme: "Smoke",
            container: container,
            projects: [project],
            repositoryRoot: root
        )
        #expect(plan.targets.isEmpty)
    }
}
