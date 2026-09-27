import Foundation
@testable import SwiftestEngine
import SwiftestModel
import SwiftestPlatform
import Testing

private let manifestTargetID = "A00000000000000000000005"

private func manifestJSON(source: String) -> String {
    """
    {
      "TestConfigurations": [{
        "IsEnabled": true,
        "Name": "Default Configuration",
        "TestTargets": [{
          "PreferredScreenCaptureFormat": "screenRecording",
          "BlueprintProviderRelativePath": "Smoke.xcodeproj",
          "ToolchainsSettingValue": [],
          "ClangProfileDataDirectoryPath": "__DERIVEDDATA__/Build/ProfileData",
          "IsMemoryTaggingAddressSanitizerEnabled": false,
          "TestLanguage": "",
          "ProductModuleName": "SmokeTests",
          "DefaultTestExecutionTimeAllowance": 600,
          "BlueprintProviderName": "Smoke",
          "UserAttachmentLifetime": "deleteOnSuccess",
          "DiagnosticCollectionPolicy": 1,
          "TestHostPath": "__PLATFORMS__/MacOSX.platform/Developer/Library/Xcode/Agents/xctest",
          "EnvironmentVariables": {
            "TERM": "dumb",
            "PERFC_ENABLE_PROFILE_MODE": "1",
            "APP_DISTRIBUTOR_ID_OVERRIDE": "com.apple.AppStore",
            "DYLD_INSERT_LIBRARIES": "/usr/lib/libRPAC.dylib",
            "IDE_CHOSEN_LOGGING_METHOD": "1",
            "PERFC_ENABLE_EXTENDED_DIAGNOSTIC_FORMAT": "1",
            "SQLITE_ENABLE_THREAD_ASSERTIONS": "1",
            "OS_ACTIVITY_DT_MODE": "YES",
            "PERFC_SUPPRESS_SYSTEM_REPORTS": "1",
            "PERFC_RESET_INSERT_LIBRARIES": "1"
          },
          "CommandLineArguments": [],
          "SystemAttachmentLifetime": "deleteOnSuccess",
          "TestingEnvironmentVariables": {
            "DYLD_LIBRARY_PATH": "__TESTROOT__/Debug:__PLATFORMS__/MacOSX.platform/Developer/usr/lib",
            "DYLD_FRAMEWORK_PATH": "__TESTROOT__/Debug:__SHAREDFRAMEWORKS__:__PLATFORMS__/MacOSX.platform/Developer/Library/Frameworks",
            "XCODE_SCHEME_NAME": "Smoke",
            "DYLD_INSERT_LIBRARIES": "__DEVELOPERUSRLIB__/libMainThreadChecker.dylib:/usr/lib/libRPAC.dylib",
            "XCODE_TEST_PLAN_NAME": "Smoke",
            "__XCODE_BUILT_PRODUCTS_DIR_PATHS": "__TESTROOT__/Debug",
            "__XPC_DYLD_LIBRARY_PATH": "__TESTROOT__/Debug",
            "__XPC_DYLD_FRAMEWORK_PATH": "__TESTROOT__/Debug",
            "PERFC_SUPPRESS_SYSTEM_REPORTS": "1"
          },
          "BlueprintName": "SmokeTests",
          "TestRegion": "",
          "TestTimeoutsEnabled": false,
          "TestBundlePath": "__TESTROOT__/Debug/SmokeTests.xctest",
          "DependentProductPaths": ["__TESTROOT__/Debug/SmokeTests.xctest"]
        }]
      }],
      "__xctestrun_metadata__": {"FormatVersion": 2},
      "ContainerInfo": {"ContainerName": "Smoke", "SchemeName": "Smoke"},
      "TestPlan": {"IsDefault": true, "Name": "Smoke"},
      "CodeCoverageBuildableInfos": [{
        "IncludeInReport": true,
        "IsStatic": false,
        "ProductPaths": ["__TESTROOT__/Debug/SmokeTests.xctest/Contents/MacOS/SmokeTests"],
        "Toolchains": ["com.apple.dt.toolchain.XcodeDefault"],
        "Name": "SmokeTests.xctest",
        "BuildableIdentifier": "A00000000000000000000005:primary",
        "Architectures": ["arm64"],
        "SourceFiles": ["\(source)"]
      }]
    }
    """
}

private struct ManifestFixture {
    let root: String
    let container: XcodeContainer
    let source: String

    func createSource(_ relativePath: ArtifactPath) throws -> String {
        try Self.createSource(relativePath, root: root)
    }

    static func createSource(_ relativePath: ArtifactPath, root: String) throws -> String {
        try FileSystemBoundary.write(
            Data("import XCTest\n".utf8),
            relativePath: relativePath,
            capability: FileSystemAuthority.grant(root: root)
        )
        return try CanonicalPathBoundary.existing(root + "/" + relativePath.rawValue)
    }

    func verifiedPlan(sources: [String]) throws -> XcodeVerifiedPlan {
        XcodeVerifiedPlan(
            planName: "Smoke",
            configurationName: "Default Configuration",
            buildConfiguration: .debug,
            targets: [XcodeVerifiedTarget(
                project: "Smoke.xcodeproj",
                identifier: manifestTargetID,
                name: "SmokeTests"
            )],
            compiledSources: try XcodeCompiledSourceSet.capture(sources, repositoryRoot: root)
        )
    }
}

private func prepareManifestFixture(root: String) throws -> ManifestFixture {
    let project = try ArtifactPath.parse("Smoke.xcodeproj")
    try FileSystemBoundary.createDirectory(
        relativePath: project,
        capability: FileSystemAuthority.grant(root: root)
    )
    let canonicalRoot = try CanonicalPathBoundary.existing(root)
    let source = try ManifestFixture.createSource(
        ArtifactPath.parse("Tests/SmokeTests.swift"),
        root: canonicalRoot
    )
    return ManifestFixture(
        root: canonicalRoot,
        container: try XcodeContainer.project(canonicalRoot + "/Smoke.xcodeproj"),
        source: source
    )
}

@Test
func xcodeV2ManifestAcceptsMeasuredStaticShape() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-v2-manifest-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let fixture = try prepareManifestFixture(root: scratch.path)
    let source = fixture.source
    let manifest = try XcodeRunManifest.decode(
        Data(manifestJSON(source: source).utf8),
        verifiedPlan: fixture.verifiedPlan(sources: [source]),
        scheme: "Smoke",
        container: fixture.container,
        repositoryRoot: fixture.root
    )
    #expect(manifest.planName == "Smoke")
    #expect(manifest.configurationName == "Default Configuration")
    #expect(manifest.targetIdentifier == manifestTargetID)
    #expect(manifest.sourceFiles == [source])
    let invocation = XcodeAppTestDriver.manifestInvocation(
        xctestrun: "/tmp/Smoke.xctestrun",
        workingDirectory: "/tmp"
    )
    #expect(invocation.arguments == ["-convert", "json", "-o", "-", "/tmp/Smoke.xctestrun"])
}

@Test
func xcodeV2ManifestRequiresExactCompiledSourceSet() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-v2-source-set-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let fixture = try prepareManifestFixture(root: scratch.path)
    let source = fixture.source
    let other = try fixture.createSource(ArtifactPath.parse("Tests/Other.swift"))
    let alias = source.replacingOccurrences(of: "/private/tmp/", with: "/tmp/")
    let aliased = try XcodeRunManifest.decode(
        Data(manifestJSON(source: alias).utf8),
        verifiedPlan: fixture.verifiedPlan(sources: [source]),
        scheme: "Smoke",
        container: fixture.container,
        repositoryRoot: fixture.root
    )
    #expect(aliased.sourceFiles == [source])
    let aliasedDuplicate = manifestJSON(source: source).replacingOccurrences(
        of: "\"SourceFiles\": [\"\(source)\"]",
        with: "\"SourceFiles\": [\"\(source)\", \"\(alias)\"]"
    )
    #expect(throws: XcodeRunManifestError.duplicateSource(alias)) {
        try XcodeRunManifest.decode(
            Data(aliasedDuplicate.utf8),
            verifiedPlan: fixture.verifiedPlan(sources: [source]),
            scheme: "Smoke",
            container: fixture.container,
            repositoryRoot: fixture.root
        )
    }
    let absent = fixture.root + "/Tests/Absent.swift"
    #expect(throws: XcodeRunManifestError.platform(.read(absent))) {
        try XcodeRunManifest.decode(
            Data(manifestJSON(source: absent).utf8),
            verifiedPlan: fixture.verifiedPlan(sources: [source]),
            scheme: "Smoke",
            container: fixture.container,
            repositoryRoot: fixture.root
        )
    }
    #expect(throws: XcodeRunManifestError.sourceSetMismatch) {
        try XcodeRunManifest.decode(
            Data(manifestJSON(source: source).utf8),
            verifiedPlan: fixture.verifiedPlan(sources: [source, other]),
            scheme: "Smoke",
            container: fixture.container,
            repositoryRoot: fixture.root
        )
    }
    #expect(throws: XcodeRunManifestError.sourceSetMismatch) {
        try XcodeRunManifest.decode(
            Data(manifestJSON(source: other).utf8),
            verifiedPlan: fixture.verifiedPlan(sources: [source]),
            scheme: "Smoke",
            container: fixture.container,
            repositoryRoot: fixture.root
        )
    }
    let extra = manifestJSON(source: source).replacingOccurrences(
        of: "\"SourceFiles\": [\"\(source)\"]",
        with: "\"SourceFiles\": [\"\(source)\", \"\(other)\"]"
    )
    #expect(throws: XcodeRunManifestError.sourceSetMismatch) {
        try XcodeRunManifest.decode(
            Data(extra.utf8),
            verifiedPlan: fixture.verifiedPlan(sources: [source]),
            scheme: "Smoke",
            container: fixture.container,
            repositoryRoot: fixture.root
        )
    }
}

@Test
func xcodeV2ManifestRejectsDynamicAndAmbiguousInputs() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-v2-manifest-adversarial-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let fixture = try prepareManifestFixture(root: scratch.path)
    let source = fixture.source
    let valid = manifestJSON(source: source)
    let arguments = valid.replacingOccurrences(
        of: "\"CommandLineArguments\": []",
        with: "\"CommandLineArguments\": [\"--hidden\"]"
    )
    #expect(throws: XcodeRunManifestError.invalidValue("CommandLineArguments")) {
        try XcodeRunManifest.decode(
            Data(arguments.utf8), verifiedPlan: fixture.verifiedPlan(sources: [source]),
            scheme: "Smoke", container: fixture.container, repositoryRoot: fixture.root
        )
    }
    let disabled = valid.replacingOccurrences(of: "\"IsEnabled\": true", with: "\"IsEnabled\": false")
    #expect(throws: XcodeRunManifestError.invalidValue("IsEnabled")) {
        try XcodeRunManifest.decode(
            Data(disabled.utf8), verifiedPlan: fixture.verifiedPlan(sources: [source]),
            scheme: "Smoke", container: fixture.container, repositoryRoot: fixture.root
        )
    }
    let environment = valid.replacingOccurrences(
        of: "\"TERM\": \"dumb\"",
        with: "\"TERM\": \"dumb\", \"INJECTED\": \"1\""
    )
    #expect(throws: XcodeRunManifestError.codec(.unknownField("INJECTED"))) {
        try XcodeRunManifest.decode(
            Data(environment.utf8), verifiedPlan: fixture.verifiedPlan(sources: [source]),
            scheme: "Smoke", container: fixture.container, repositoryRoot: fixture.root
        )
    }
    let external = valid.replacingOccurrences(of: source, with: "/private/tmp/External.swift")
    #expect(throws: XcodeRunManifestError.sourceOutsideRepository("/private/tmp/External.swift")) {
        try XcodeRunManifest.decode(
            Data(external.utf8), verifiedPlan: fixture.verifiedPlan(sources: [source]),
            scheme: "Smoke", container: fixture.container, repositoryRoot: fixture.root
        )
    }
}

@Test
func xcodeV2ManifestRejectsUnknownFieldsAndIdentityDrift() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-v2-manifest-identity-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let fixture = try prepareManifestFixture(root: scratch.path)
    let source = fixture.source
    let valid = manifestJSON(source: source)
    let unknown = valid.replacingOccurrences(
        of: "\"IsDefault\": true",
        with: "\"IsDefault\": true, \"HiddenPlan\": true"
    )
    #expect(throws: XcodeRunManifestError.codec(.unknownField("HiddenPlan"))) {
        try XcodeRunManifest.decode(
            Data(unknown.utf8), verifiedPlan: fixture.verifiedPlan(sources: [source]),
            scheme: "Smoke", container: fixture.container, repositoryRoot: fixture.root
        )
    }
    let wrongTarget = valid.replacingOccurrences(
        of: "A00000000000000000000005:primary",
        with: "A00000000000000000000006:primary"
    )
    #expect(throws: XcodeRunManifestError.invalidValue("BuildableIdentifier")) {
        try XcodeRunManifest.decode(
            Data(wrongTarget.utf8), verifiedPlan: fixture.verifiedPlan(sources: [source]),
            scheme: "Smoke", container: fixture.container, repositoryRoot: fixture.root
        )
    }
    let oldVersion = valid.replacingOccurrences(of: "\"FormatVersion\": 2", with: "\"FormatVersion\": 1")
    #expect(throws: XcodeRunManifestError.invalidValue("FormatVersion")) {
        try XcodeRunManifest.decode(
            Data(oldVersion.utf8), verifiedPlan: fixture.verifiedPlan(sources: [source]),
            scheme: "Smoke", container: fixture.container, repositoryRoot: fixture.root
        )
    }
}
