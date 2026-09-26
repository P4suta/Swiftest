import Foundation
@testable import SwiftestEngine
import SwiftestPlatform
import Testing

private let minimalProject = """
{
    archiveVersion = 1;
    classes = {};
    objectVersion = 77;
    objects = {
        ROOT = { isa = PBXProject; projectDirPath = ""; projectRoot = ""; };
        GROUP = { isa = PBXGroup; sourceTree = "<group>"; path = Sources; };
        FILE = { isa = PBXFileReference; sourceTree = "<group>"; path = Sources/App.swift; };
        TARGET = { isa = PBXNativeTarget; productReference = PRODUCT; };
        PRODUCT = { isa = PBXFileReference; sourceTree = BUILT_PRODUCTS_DIR; path = App.app; };
        CONFIG = { isa = XCBuildConfiguration; buildSettings = { SWIFT_VERSION = 6.0; SDKROOT = iphoneos; }; };
    };
    rootObject = ROOT;
}
"""

private let minimalScheme = """
<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
    <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
        <BuildActionEntries>
            <BuildActionEntry buildForTesting="YES" buildForRunning="YES">
                <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="TARGET" BuildableName="App.app" BlueprintName="App" ReferencedContainer="container:App.xcodeproj"/>
            </BuildActionEntry>
        </BuildActionEntries>
    </BuildAction>
    <TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="NO">
        <Testables>
            <TestableReference skipped="NO">
                <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="TESTS" BuildableName="AppTests.xctest" BlueprintName="AppTests" ReferencedContainer="container:App.xcodeproj"/>
            </TestableReference>
        </Testables>
    </TestAction>
</Scheme>
"""

@Test
func xcodeProjectAcceptsOnlyStaticContainedReferences() throws {
    try XcodeInputClosure.inspectProject(Data(minimalProject.utf8))
    let ordinaryComment = minimalProject.replacingOccurrences(
        of: "FILE = {",
        with: "FILE /* source file */ = {"
    )
    try XcodeInputClosure.inspectProject(Data(ordinaryComment.utf8))
    let typedSwift = minimalProject.replacingOccurrences(
        of: "path = Sources/App.swift;",
        with: "path = Sources/App.swift; lastKnownFileType = sourcecode.swift;"
    )
    try XcodeInputClosure.inspectProject(Data(typedSwift.utf8))
    let systemFramework = minimalProject.replacingOccurrences(
        of: "FILE = { isa = PBXFileReference; sourceTree = \"<group>\"; path = Sources/App.swift; };",
        with: "FILE = { isa = PBXFileReference; sourceTree = SDKROOT; path = System/Library/Frameworks/Foundation.framework; };"
    )
    try XcodeInputClosure.inspectProject(Data(systemFramework.utf8))
}

@Test
func xcodeProjectRejectsTransitiveAndUnknownLocalSourceTypes() throws {
    for path in [
        "Sources/Native.c", "Sources/Native.m", "Sources/Native.mm",
        "Sources/Native.cc", "Sources/Native.cpp", "Sources/Native.cxx",
        "Sources/Native.h", "Sources/Native.hh", "Sources/Native.hpp",
        "Sources/Native.hxx", "Sources/Native.pch", "Sources/Native.inc",
        "Sources/Native.modulemap", "Sources/Native.def", "Sources/Native.S",
        "Sources/Shader.metal", "Sources/Shader.metalh",
        "Sources/Interface.swiftinterface", "Sources/Module.swiftmodule",
        "Sources/Unknown.zig", "Sources/Unknown.rs", "Sources/Unknown",
        "Libraries/Local.framework", "Libraries/Local.xcframework", "Libraries/Local.a",
    ] {
        let project = minimalProject.replacingOccurrences(of: "Sources/App.swift", with: path)
        #expect(throws: XcodeInputClosureError.unsupportedProjectFeature("local-file-type")) {
            try XcodeInputClosure.inspectProject(Data(project.utf8))
        }
    }
}

@Test
func xcodeProjectRejectsMasqueradingFileTypes() throws {
    let explicit = minimalProject.replacingOccurrences(
        of: "path = Sources/App.swift;",
        with: "path = Sources/App.swift; explicitFileType = sourcecode.c.h;"
    )
    #expect(throws: XcodeInputClosureError.unsupportedProjectFeature("explicit-file-type")) {
        try XcodeInputClosure.inspectProject(Data(explicit.utf8))
    }
    let declared = minimalProject.replacingOccurrences(
        of: "path = Sources/App.swift;",
        with: "path = Sources/App.swift; lastKnownFileType = sourcecode.c.h;"
    )
    #expect(throws: XcodeInputClosureError.unsupportedProjectFeature("declared-file-type")) {
        try XcodeInputClosure.inspectProject(Data(declared.utf8))
    }
}

@Test
func xcodeProjectRejectsSynchronizedAndVersionedSourceGroups() throws {
    for kind in ["PBXFileSystemSynchronizedRootGroup", "XCVersionGroup"] {
        let project = minimalProject.replacingOccurrences(
            of: "GROUP = { isa = PBXGroup;",
            with: "GROUP = { isa = \(kind);"
        )
        #expect(throws: XcodeInputClosureError.unsupportedProjectFeature(kind)) {
            try XcodeInputClosure.inspectProject(Data(project.utf8))
        }
    }
}

@Test
func xcodeProjectRejectsParentAndAbsoluteSourceReferences() throws {
    let unsafePaths = ["../Shared/Feature.swift", "/private/tmp/Shared/Feature.swift"]
        + SourceExcludedDirectory.allCases.map { $0.rawValue + "/Feature.swift" }
    for unsafe in unsafePaths {
        let project = minimalProject.replacingOccurrences(of: "Sources/App.swift", with: unsafe)
        #expect(throws: XcodeInputClosureError.unsafeReference(unsafe)) {
            try XcodeInputClosure.inspectProject(Data(project.utf8))
        }
    }
}

@Test
func xcodeProjectRejectsDynamicAndAbsoluteSourceTrees() throws {
    let dynamic = minimalProject.replacingOccurrences(
        of: "Sources/App.swift",
        with: "\"$(EXTERNAL_ROOT)/Feature.swift\""
    )
    #expect(throws: XcodeInputClosureError.unsafeReference("$(EXTERNAL_ROOT)/Feature.swift")) {
        try XcodeInputClosure.inspectProject(Data(dynamic.utf8))
    }
    let absoluteTree = minimalProject.replacingOccurrences(
        of: "FILE = { isa = PBXFileReference; sourceTree = \"<group>\";",
        with: "FILE = { isa = PBXFileReference; sourceTree = \"<absolute>\";"
    )
    #expect(throws: XcodeInputClosureError.unsafeReference("<absolute>")) {
        try XcodeInputClosure.inspectProject(Data(absoluteTree.utf8))
    }
    let projectRoot = minimalProject.replacingOccurrences(
        of: "projectDirPath = \"\";",
        with: "projectDirPath = ../Shared;"
    )
    #expect(throws: XcodeInputClosureError.unsafeReference("project-directory")) {
        try XcodeInputClosure.inspectProject(Data(projectRoot.utf8))
    }
}

@Test
func xcodeProjectRejectsAmbiguousOrExecutableMetadata() throws {
    let duplicate = minimalProject.replacingOccurrences(
        of: "path = Sources/App.swift;",
        with: "path = Sources/App.swift; path = ../Shared/Feature.swift;"
    )
    #expect(throws: XcodeInputClosureError.duplicateProjectKey("path")) {
        try XcodeInputClosure.inspectProject(Data(duplicate.utf8))
    }
    let script = minimalProject.replacingOccurrences(
        of: "CONFIG = {",
        with: "SCRIPT = { isa = PBXShellScriptBuildPhase; }; CONFIG = {"
    )
    #expect(throws: XcodeInputClosureError.unsupportedProjectFeature("PBXShellScriptBuildPhase")) {
        try XcodeInputClosure.inspectProject(Data(script.utf8))
    }
    let flags = minimalProject.replacingOccurrences(
        of: "SWIFT_VERSION = 6.0;",
        with: "SWIFT_VERSION = 6.0; OTHER_SWIFT_FLAGS = -I/private/tmp/External;"
    )
    #expect(throws: XcodeInputClosureError.unsupportedBuildSetting("OTHER_SWIFT_FLAGS")) {
        try XcodeInputClosure.inspectProject(Data(flags.utf8))
    }
    let configuration = minimalProject.replacingOccurrences(
        of: "CONFIG = { isa = XCBuildConfiguration;",
        with: "CONFIG = { isa = XCBuildConfiguration; baseConfigurationReference = EXTERNAL;"
    )
    #expect(throws: XcodeInputClosureError.unsupportedProjectFeature("xcconfig")) {
        try XcodeInputClosure.inspectProject(Data(configuration.utf8))
    }
}

@Test
func xcodeWorkspaceRejectsExternalAndDynamicProjectLocations() throws {
    let valid = """
    <?xml version="1.0" encoding="UTF-8"?>
    <Workspace version="1.0"><FileRef location="group:App.xcodeproj"/></Workspace>
    """
    #expect(try XcodeInputClosure.inspectWorkspace(Data(valid.utf8)) == ["App.xcodeproj"])
    for unsafe in ["group:../External.xcodeproj", "group:/private/tmp/External.xcodeproj",
        "absolute:/private/tmp/External.xcodeproj", "group:$(ROOT)/External.xcodeproj"] {
        let workspace = valid.replacingOccurrences(of: "group:App.xcodeproj", with: unsafe)
        #expect(throws: XcodeInputClosureError.self) {
            let projects = try XcodeInputClosure.inspectWorkspace(Data(workspace.utf8))
            #expect(projects.isEmpty)
        }
    }
    let documentType = valid.replacingOccurrences(
        of: "<Workspace",
        with: "<!DOCTYPE Workspace [<!ENTITY external SYSTEM \"file:///private/tmp/External.xcodeproj\">]><Workspace"
    )
    #expect(throws: XcodeInputClosureError.invalidWorkspace) {
        let projects = try XcodeInputClosure.inspectWorkspace(Data(documentType.utf8))
        #expect(projects.isEmpty)
    }
}

@Test
func xcodeSchemeAcceptsOnlyStaticProjectReferences() throws {
    let references = try XcodeSchemeClosure.inspect(Data(minimalScheme.utf8))
    #expect(references == ["App.xcodeproj", "App.xcodeproj"])
    try XcodeSchemeClosure.validateReferences(
        references,
        base: "/private/tmp/repository",
        projects: ["/private/tmp/repository/App.xcodeproj"],
        repositoryRoot: "/private/tmp/repository"
    )
    #expect(throws: XcodeInputClosureError.externalContainer("App.xcodeproj")) {
        try XcodeSchemeClosure.validateReferences(
            references,
            base: "/private/tmp/repository",
            projects: ["/private/tmp/repository/Other.xcodeproj"],
            repositoryRoot: "/private/tmp/repository"
        )
    }
}

@Test
func xcodeSchemeRejectsPreAndPostActionsBeforeBuild() throws {
    let preAction = minimalScheme.replacingOccurrences(
        of: "<BuildActionEntries>",
        with: "<PreActions><ExecutionAction ActionType=\"Xcode.IDEStandardExecutionActionsCore.ExecutionActionType.ShellScriptAction\"/></PreActions><BuildActionEntries>"
    )
    #expect(throws: XcodeInputClosureError.unsupportedSchemeFeature("PreActions")) {
        let references = try XcodeSchemeClosure.inspect(Data(preAction.utf8))
        #expect(references.isEmpty)
    }
    let postAction = minimalScheme.replacingOccurrences(
        of: "</TestAction>",
        with: "<PostActions/></TestAction>"
    )
    #expect(throws: XcodeInputClosureError.unsupportedSchemeFeature("PostActions")) {
        let references = try XcodeSchemeClosure.inspect(Data(postAction.utf8))
        #expect(references.isEmpty)
    }
}

@Test
func xcodeSchemeRejectsExternalAndAmbiguousBuildableReferences() throws {
    for unsafe in ["container:../Shared/External.xcodeproj",
        "container:/private/tmp/External.xcodeproj",
        "container:$(EXTERNAL_PROJECT)/External.xcodeproj"] {
        let scheme = minimalScheme.replacingOccurrences(
            of: "container:App.xcodeproj",
            with: unsafe
        )
        #expect(throws: XcodeInputClosureError.self) {
            let references = try XcodeSchemeClosure.inspect(Data(scheme.utf8))
            #expect(references.isEmpty)
        }
    }
    let remote = minimalScheme.replacingOccurrences(
        of: "container:App.xcodeproj",
        with: "absolute:/private/tmp/External.xcodeproj"
    )
    #expect(throws: XcodeInputClosureError.invalidScheme) {
        let references = try XcodeSchemeClosure.inspect(Data(remote.utf8))
        #expect(references.isEmpty)
    }
    let duplicate = minimalScheme.replacingOccurrences(
        of: "</BuildAction>",
        with: "</BuildAction><BuildAction/>"
    )
    #expect(throws: XcodeInputClosureError.invalidScheme) {
        let references = try XcodeSchemeClosure.inspect(Data(duplicate.utf8))
        #expect(references.isEmpty)
    }
}

@Test
func xcodeSchemeRejectsUnverifiedTestPlansAndEnvironment() throws {
    let plan = minimalScheme.replacingOccurrences(
        of: "<Testables>",
        with: "<TestPlans><TestPlanReference reference=\"container:External.xctestplan\"/></TestPlans><Testables>"
    )
    #expect(throws: XcodeInputClosureError.unsupportedSchemeFeature("TestPlans")) {
        let references = try XcodeSchemeClosure.inspect(Data(plan.utf8))
        #expect(references.isEmpty)
    }
    let environment = minimalScheme.replacingOccurrences(
        of: "</TestAction>",
        with: "<EnvironmentVariables><EnvironmentVariable key=\"SOURCE_ROOT\" value=\"/private/tmp/External\"/></EnvironmentVariables></TestAction>"
    )
    #expect(throws: XcodeInputClosureError.unsupportedSchemeFeature("EnvironmentVariables")) {
        let references = try XcodeSchemeClosure.inspect(Data(environment.utf8))
        #expect(references.isEmpty)
    }
    let workingDirectory = minimalScheme.replacingOccurrences(
        of: "</Scheme>",
        with: "<LaunchAction useCustomWorkingDirectory=\"YES\"/></Scheme>"
    )
    #expect(throws: XcodeInputClosureError.unsupportedSchemeFeature("custom-working-directory")) {
        let references = try XcodeSchemeClosure.inspect(Data(workingDirectory.utf8))
        #expect(references.isEmpty)
    }
    let documentType = minimalScheme.replacingOccurrences(
        of: "<Scheme",
        with: "<!DOCTYPE Scheme [<!ENTITY external SYSTEM \"file:///private/tmp/External\">]><Scheme"
    )
    #expect(throws: XcodeInputClosureError.invalidScheme) {
        let references = try XcodeSchemeClosure.inspect(Data(documentType.utf8))
        #expect(references.isEmpty)
    }
}
