import Foundation
import SwiftestCodec
import SwiftestPlatform

public enum XcodeInputClosureError: Error, Equatable, Sendable {
    case platform(PlatformError)
    case invalidProjectSyntax
    case duplicateProjectKey(String)
    case unsupportedProjectObject(String)
    case unsupportedBuildSetting(String)
    case unsupportedProjectFeature(String)
    case unsafeReference(String)
    case externalContainer(String)
    case invalidWorkspace
    case invalidScheme
    case ambiguousScheme
    case unsupportedSchemeFeature(String)
    case invalidTestPlan(String)
    case testPlanCodec(StrictJSONError)
    case sourceGraph(XcodeSourceGraphError)
}

public enum XcodeSourceGraphError: Error, Equatable, Sendable {
    case missingReference(String)
    case unexpectedObject(String)
    case unsupportedFields(String)
    case duplicateReference(String)
    case missingSources(String)
    case orphanObject(String)
}

struct XcodeVerifiedProject {
    let path: String
    let targetIdentifiers: Set<String>
    let sourcePathsByTarget: [String: Set<String>]
}

private struct InspectedXcodeProject {
    let objects: [String: OpenStepProjectValue]
    let rootIdentifier: String
    let targetIdentifiers: Set<String>
}

enum XcodeInputClosure {
    static func verify(
        container: XcodeContainer,
        repositoryRoot: String,
        scheme: String
    ) throws(XcodeInputClosureError) -> XcodeVerifiedPlan {
        let root: String
        do {
            root = try CanonicalPathBoundary.directory(repositoryRoot)
        } catch let error {
            throw .platform(error)
        }
        let projects: [XcodeVerifiedProject]
        switch container.kind {
        case .project:
            projects = [try verifyProject(path: container.path, root: root)]
        case .workspace:
            let workspace = try contained(path: container.path, root: root)
            let contents = workspace + "/contents.xcworkspacedata"
            let kind: FileEntryKind
            do {
                kind = try FileSystemBoundary.entryKind(path: contents)
            } catch let error {
                throw .platform(error)
            }
            guard kind == .file else {
                throw .invalidWorkspace
            }
            let data: Data
            do {
                data = try FileSystemBoundary.read(path: contents)
            } catch let error {
                throw .platform(error)
            }
            let references = try inspectWorkspace(data)
            let parent = URL(fileURLWithPath: workspace).deletingLastPathComponent().path
            var verified: [XcodeVerifiedProject] = []
            for reference in references {
                let project = parent + "/" + reference
                verified.append(try verifyProject(path: project, root: root))
            }
            projects = verified
        }
        return try XcodeSchemeClosure.verify(
            scheme: scheme,
            container: container,
            projects: projects,
            repositoryRoot: root
        )
    }

    static func inspectProject(_ data: Data) throws(XcodeInputClosureError) {
        let inspected = try inspectProjectObjects(data)
        guard !inspected.targetIdentifiers.isEmpty else {
            throw .invalidProjectSyntax
        }
    }

    private static func inspectProjectObjects(
        _ data: Data
    ) throws(XcodeInputClosureError) -> InspectedXcodeProject {
        var parser = OpenStepProjectParser(data: data)
        let root = try parser.parse().record()
        guard Set(root.keys) == ["archiveVersion", "classes", "objectVersion", "objects", "rootObject"],
            try root["archiveVersion"]?.string() == "1",
            let version = try root["objectVersion"]?.string(),
            !version.isEmpty,
            version.allSatisfy(\.isNumber),
            try root["classes"]?.record().isEmpty == true,
            let objects = try root["objects"]?.record(),
            let rootID = try root["rootObject"]?.string(),
            let project = objects[rootID],
            try project.record()["isa"]?.string() == "PBXProject" else {
            throw .invalidProjectSyntax
        }
        var productIDs: Set<String> = []
        var targetIDs: Set<String> = []
        for id in objects.keys.sorted() {
            guard let value = objects[id] else {
                throw .invalidProjectSyntax
            }
            let object = try value.record()
            if try object["isa"]?.string() == "PBXNativeTarget" {
                guard let product = try object["productReference"]?.string() else {
                    throw .invalidProjectSyntax
                }
                productIDs.insert(product)
                targetIDs.insert(id)
            }
        }
        for id in objects.keys.sorted() {
            guard let value = objects[id] else {
                throw .invalidProjectSyntax
            }
            let object = try value.record()
            guard let kind = try object["isa"]?.string() else {
                throw .invalidProjectSyntax
            }
            try inspect(object: object, kind: kind, id: id, productIDs: productIDs)
        }
        return InspectedXcodeProject(
            objects: objects,
            rootIdentifier: rootID,
            targetIdentifiers: targetIDs
        )
    }

    static func inspectWorkspace(_ data: Data) throws(XcodeInputClosureError) -> [String] {
        let workspace: XcodeXMLNode
        do {
            workspace = try XcodeXML.parse(data, maximumBytes: 1_048_576)
        } catch {
            throw .invalidWorkspace
        }
        guard workspace.name == "Workspace",
            workspace.attributes == ["version": "1.0"],
            !workspace.children.isEmpty else {
            throw .invalidWorkspace
        }
        var projects: [String] = []
        for reference in workspace.children {
            guard reference.name == "FileRef",
                reference.children.isEmpty,
                reference.attributes.count == 1,
                let location = reference.attributes["location"],
                location.hasPrefix("group:") else {
                throw .invalidWorkspace
            }
            let project = String(location.dropFirst("group:".count))
            guard project.hasSuffix(".xcodeproj") else {
                throw .invalidWorkspace
            }
            try validateRelativeReference(project)
            projects.append(project)
        }
        guard Set(projects).count == projects.count else {
            throw .invalidWorkspace
        }
        return projects.sorted()
    }

    static func verifyProject(
        path: String,
        root: String
    ) throws(XcodeInputClosureError) -> XcodeVerifiedProject {
        let project = try contained(path: path, root: root)
        guard project.hasSuffix(".xcodeproj") else {
            throw .externalContainer(path)
        }
        let kind: FileEntryKind
        do {
            kind = try FileSystemBoundary.entryKind(path: project + "/project.pbxproj")
        } catch let error {
            throw .platform(error)
        }
        guard kind == .file else {
            throw .unsupportedProjectFeature(project)
        }
        let data: Data
        do {
            data = try FileSystemBoundary.read(path: project + "/project.pbxproj")
        } catch let error {
            throw .platform(error)
        }
        let inspected = try inspectProjectObjects(data)
        guard !inspected.targetIdentifiers.isEmpty else {
            throw .invalidProjectSyntax
        }
        var graph = XcodeSourceGraphVerifier(
            projectDirectory: URL(fileURLWithPath: project).deletingLastPathComponent().path,
            repositoryRoot: root,
            inspected: inspected
        )
        let paths = try graph.verify()
        return XcodeVerifiedProject(
            path: project,
            targetIdentifiers: inspected.targetIdentifiers,
            sourcePathsByTarget: paths
        )
    }

    static func contained(path: String, root: String) throws(XcodeInputClosureError) -> String {
        let resolved: String
        do {
            resolved = try CanonicalPathBoundary.existing(path)
        } catch {
            throw .externalContainer(path)
        }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard resolved.hasPrefix(prefix) else {
            throw .externalContainer(path)
        }
        let relative = String(resolved.dropFirst(prefix.count))
        guard let first = relative.split(separator: "/").first,
            !SourceExclusionPolicy.excludesDirectory(relativePath: String(first)) else {
            throw .externalContainer(path)
        }
        return resolved
    }

    private static func inspect(
        object: [String: OpenStepProjectValue],
        kind: String,
        id: String,
        productIDs: Set<String>
    ) throws(XcodeInputClosureError) {
        switch kind {
        case "PBXFileReference":
            guard let path = try object["path"]?.string() else {
                throw .unsafeReference(id)
            }
            guard let tree = try object["sourceTree"]?.string() else {
                throw .unsafeReference(id)
            }
            if tree == "BUILT_PRODUCTS_DIR" {
                guard productIDs.contains(id) else {
                    throw .unsafeReference(id)
                }
                try validateRelativeReference(path)
            } else if tree == "SDKROOT" {
                guard (path.hasPrefix("System/Library/Frameworks/") && path.hasSuffix(".framework"))
                    || (path.hasPrefix("usr/lib/") && path.hasSuffix(".tbd")) else {
                    throw .unsafeReference(path)
                }
                try validateRelativeReference(path)
            } else {
                try validateSourceTree(tree, path: path)
                try validateLocalFileReference(object, path: path)
            }
        case "PBXGroup", "PBXVariantGroup":
            guard let tree = try object["sourceTree"]?.string() else {
                throw .unsafeReference(id)
            }
            try validateSourceTree(tree, path: try object["path"]?.string())
        case "XCBuildConfiguration":
            if object["baseConfigurationReference"] != nil {
                throw .unsupportedProjectFeature("xcconfig")
            }
            guard let settings = try object["buildSettings"]?.record() else {
                throw .invalidProjectSyntax
            }
            for key in settings.keys.sorted() {
                guard let value = settings[key] else {
                    throw .invalidProjectSyntax
                }
                try validateBuildSetting(key: key, value: value)
            }
        case "PBXBuildFile":
            if object["productRef"] != nil || object["platformFilter"] != nil {
                throw .unsupportedProjectFeature("build-file")
            }
            if let settings = try object["settings"]?.record() {
                let allowedAttributes: Set<String> = ["Public", "Private", "Project"]
                let attributes = try settings["ATTRIBUTES"]?.list()
                var names: [String] = []
                if let attributes {
                    for attribute in attributes {
                        names.append(try attribute.string())
                    }
                }
                guard Set(settings.keys) == ["ATTRIBUTES"],
                    attributes != nil,
                    names.allSatisfy({ allowedAttributes.contains($0) }) else {
                    throw .unsupportedProjectFeature("build-file-settings")
                }
            }
        case "PBXProject":
            guard try object["projectDirPath"]?.string() == "",
                try object["projectRoot"]?.string() == "" else {
                throw .unsafeReference("project-directory")
            }
            try requireEmpty(object["projectReferences"], feature: "project-dependency")
            try requireEmpty(object["packageReferences"], feature: "package-dependency")
        case "PBXNativeTarget":
            try requireEmpty(object["packageProductDependencies"], feature: "package-dependency")
            try requireEmpty(object["buildRules"], feature: "build-rule")
        case "PBXTargetDependency":
            if object["targetProxy"] != nil {
                throw .unsupportedProjectFeature("target-proxy")
            }
        case "PBXCopyFilesBuildPhase", "PBXFrameworksBuildPhase", "PBXHeadersBuildPhase",
            "PBXResourcesBuildPhase", "PBXSourcesBuildPhase", "PBXRezBuildPhase", "XCConfigurationList":
            break
        case "PBXShellScriptBuildPhase", "PBXBuildRule", "PBXAppleScriptBuildPhase",
            "PBXAggregateTarget", "PBXLegacyTarget", "PBXReferenceProxy",
            "PBXContainerItemProxy", "XCRemoteSwiftPackageReference",
            "XCLocalSwiftPackageReference", "XCSwiftPackageProductDependency",
            "PBXFileSystemSynchronizedBuildFileExceptionSet",
            "PBXFileSystemSynchronizedRootGroup", "XCVersionGroup":
            throw .unsupportedProjectFeature(kind)
        default:
            throw .unsupportedProjectObject(kind)
        }
    }

    private static func validateSourceTree(
        _ tree: String,
        path: String?
    ) throws(XcodeInputClosureError) {
        guard tree == "<group>" || tree == "SOURCE_ROOT" || tree == "PROJECT_DIR" else {
            throw .unsafeReference(tree)
        }
        if let path {
            try validateRelativeReference(path)
        }
    }

    private static func validateLocalFileReference(
        _ object: [String: OpenStepProjectValue],
        path: String
    ) throws(XcodeInputClosureError) {
        let fileExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        guard let knownType = localFileTypes[fileExtension] else {
            throw .unsupportedProjectFeature("local-file-type")
        }
        if object["explicitFileType"] != nil {
            throw .unsupportedProjectFeature("explicit-file-type")
        }
        if let declaredType = try object["lastKnownFileType"]?.string(),
            !knownType.contains(declaredType) {
            throw .unsupportedProjectFeature("declared-file-type")
        }
    }

    private static let localFileTypes: [String: Set<String>] = [
        "swift": ["sourcecode.swift"],
        "xcassets": ["folder.assetcatalog"],
        "storyboard": ["file.storyboard"],
        "xib": ["file.xib"],
        "strings": ["text.plist.strings"],
        "stringsdict": ["text.plist.stringsdict"],
        "xcstrings": ["text.json.xcstrings"],
        "plist": ["text.plist.xml"],
        "entitlements": ["text.plist.entitlements", "text.plist.xml"],
        "png": ["image.png"],
        "jpg": ["image.jpeg"],
        "jpeg": ["image.jpeg"],
        "heic": ["image.heic"],
        "pdf": ["image.pdf"],
        "svg": ["image.svg"],
        "json": ["text.json"],
        "txt": ["text"],
    ]

    private static func requireEmpty(
        _ value: OpenStepProjectValue?,
        feature: String
    ) throws(XcodeInputClosureError) {
        if let value {
            let entries = try value.list()
            if !entries.isEmpty {
                throw .unsupportedProjectFeature(feature)
            }
        }
    }

    static func validateRelativeReference(_ path: String) throws(XcodeInputClosureError) {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty,
            !path.hasPrefix("/"),
            !path.hasPrefix("~"),
            !path.contains("$"),
            !path.contains("\\"),
            !path.contains(":"),
            !path.contains("%"),
            path.unicodeScalars.allSatisfy({ $0.value > 31 && $0.value != 127 }),
            components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".."
                && !SourceExclusionPolicy.excludesDirectory(relativePath: String($0)) }) else {
            throw .unsafeReference(path)
        }
    }

    private static func validateBuildSetting(
        key: String,
        value: OpenStepProjectValue
    ) throws(XcodeInputClosureError) {
        if pathSettings.contains(key) {
            let path = try value.string()
            try validateRelativeReference(path)
            return
        }
        guard safeSettings.contains(key) || key.hasPrefix("INFOPLIST_KEY_")
            || key.hasPrefix("CLANG_WARN_") || key.hasPrefix("GCC_WARN_") else {
            throw .unsupportedBuildSetting(key)
        }
        let values = try value.scalarStrings()
        for item in values where item.contains("$") {
            if key != "PRODUCT_NAME" || item != "$(TARGET_NAME)" {
                throw .unsupportedBuildSetting(key)
            }
        }
        if key == "SDKROOT" {
            guard values.count == 1,
                ["macosx", "iphoneos", "iphonesimulator", "appletvos", "appletvsimulator",
                 "watchos", "watchsimulator", "xros", "xrsimulator"].contains(values[0]) else {
                throw .unsupportedBuildSetting(key)
            }
        }
    }

    private static let pathSettings: Set<String> = ["CODE_SIGN_ENTITLEMENTS", "INFOPLIST_FILE"]

    private static let safeSettings: Set<String> = [
        "ASSETCATALOG_COMPILER_APPICON_NAME", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME",
        "CLANG_ANALYZER_NONNULL", "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION",
        "CLANG_CXX_LANGUAGE_STANDARD", "CLANG_ENABLE_MODULES", "CLANG_ENABLE_OBJC_ARC",
        "CLANG_ENABLE_OBJC_WEAK", "COPY_PHASE_STRIP", "CURRENT_PROJECT_VERSION",
        "DEBUG_INFORMATION_FORMAT", "DEVELOPMENT_TEAM", "ENABLE_HARDENED_RUNTIME",
        "ENABLE_PREVIEWS", "ENABLE_STRICT_OBJC_MSGSEND", "ENABLE_TESTABILITY",
        "ENABLE_USER_SCRIPT_SANDBOXING", "GCC_C_LANGUAGE_STANDARD", "GCC_DYNAMIC_NO_PIC",
        "GCC_NO_COMMON_BLOCKS", "GCC_OPTIMIZATION_LEVEL", "GCC_PREPROCESSOR_DEFINITIONS",
        "GENERATE_INFOPLIST_FILE", "IPHONEOS_DEPLOYMENT_TARGET",
        "LOCALIZATION_PREFERS_STRING_CATALOGS", "MACOSX_DEPLOYMENT_TARGET",
        "MARKETING_VERSION", "MTL_ENABLE_DEBUG_INFO", "MTL_FAST_MATH",
        "ONLY_ACTIVE_ARCH", "PRODUCT_BUNDLE_IDENTIFIER", "PRODUCT_NAME",
        "REGISTER_APP_GROUPS", "SDKROOT", "STRING_CATALOG_GENERATE_SYMBOLS",
        "SUPPORTED_PLATFORMS", "SUPPORTS_MACCATALYST",
        "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD", "SWIFT_ACTIVE_COMPILATION_CONDITIONS",
        "SWIFT_EMIT_LOC_STRINGS", "SWIFT_OPTIMIZATION_LEVEL", "SWIFT_STRICT_CONCURRENCY",
        "SWIFT_VERSION", "TARGETED_DEVICE_FAMILY", "TVOS_DEPLOYMENT_TARGET",
        "VALIDATE_PRODUCT", "WATCHOS_DEPLOYMENT_TARGET", "XROS_DEPLOYMENT_TARGET",
    ]
}

private struct XcodeSourceGraphVerifier {
    let projectDirectory: String
    let repositoryRoot: String
    let inspected: InspectedXcodeProject
    private var visited: Set<String> = []
    private var productIdentifiers: Set<String> = []
    private var fileTrees: [String: String] = [:]
    private var localFiles: [String: String] = [:]

    mutating func verify() throws(XcodeInputClosureError) -> [String: Set<String>] {
        for target in inspected.targetIdentifiers.sorted() {
            let value = try object(target, kind: "PBXNativeTarget")
            let product = try requiredString(value, key: "productReference", id: target)
            guard productIdentifiers.insert(product).inserted else {
                throw .sourceGraph(.duplicateReference(product))
            }
        }
        let project = try object(inspected.rootIdentifier, kind: "PBXProject")
        try visit(inspected.rootIdentifier)
        try fields(
            project,
            required: ["isa", "buildConfigurationList", "mainGroup", "productRefGroup", "projectDirPath", "projectRoot", "targets"],
            optional: ["attributes", "compatibilityVersion", "developmentRegion", "hasScannedForEncodings", "knownRegions"],
            id: inspected.rootIdentifier
        )
        if let attributes = project["attributes"] {
            let values = try attributes.record()
            guard Set(values.keys).isSubset(of: ["LastUpgradeCheck"]) else {
                throw .sourceGraph(.unsupportedFields(inspected.rootIdentifier + ":attributes"))
            }
            for value in values.values {
                let text = try value.string()
                guard !text.isEmpty, text.allSatisfy(\.isNumber) else {
                    throw .sourceGraph(.unexpectedObject(inspected.rootIdentifier + ":attributes"))
                }
            }
        }
        for key in ["compatibilityVersion", "developmentRegion", "hasScannedForEncodings"] {
            if let value = project[key] {
                let text = try value.string()
                guard !text.isEmpty else {
                    throw .sourceGraph(.unexpectedObject(inspected.rootIdentifier + ":" + key))
                }
            }
        }
        if let regions = project["knownRegions"] {
            let names = try strings(regions, id: inspected.rootIdentifier + ":knownRegions")
            guard Set(names).count == names.count else {
                throw .sourceGraph(.duplicateReference(inspected.rootIdentifier + ":knownRegions"))
            }
        }
        let rootGroup = try requiredString(project, key: "mainGroup", id: inspected.rootIdentifier)
        let productGroup = try requiredString(project, key: "productRefGroup", id: inspected.rootIdentifier)
        try visitGroup(rootGroup, parent: projectDirectory)
        guard visited.contains(productGroup) else {
            throw .sourceGraph(.missingReference(productGroup))
        }
        let projectTargets = try references(project, key: "targets", id: inspected.rootIdentifier)
        guard !projectTargets.isEmpty, Set(projectTargets) == inspected.targetIdentifiers else {
            throw .sourceGraph(.unexpectedObject(inspected.rootIdentifier + ":targets"))
        }
        try visitConfigurationList(try requiredString(project, key: "buildConfigurationList", id: inspected.rootIdentifier))
        var sourcePathsByTarget: [String: Set<String>] = [:]
        for target in projectTargets {
            sourcePathsByTarget[target] = try visitTarget(target)
        }
        for identifier in inspected.objects.keys.sorted() where !visited.contains(identifier) {
            throw .sourceGraph(.orphanObject(identifier))
        }
        return sourcePathsByTarget
    }

    private mutating func visitGroup(_ id: String, parent: String) throws(XcodeInputClosureError) {
        let group = try object(id, kind: "PBXGroup")
        try visit(id)
        try fields(
            group,
            required: ["isa", "children", "sourceTree"],
            optional: ["name", "path"],
            id: id
        )
        let tree = try requiredString(group, key: "sourceTree", id: id)
        let base: String
        switch tree {
        case "<group>":
            base = parent
        case "SOURCE_ROOT", "PROJECT_DIR":
            base = projectDirectory
        default:
            throw .unsafeReference(tree)
        }
        let directory: String
        if let value = group["path"] {
            directory = try localPath(try value.string(), base: base, kind: .directory)
        } else {
            directory = base
        }
        if let value = group["name"] {
            let name = try value.string()
            guard !name.isEmpty else {
                throw .sourceGraph(.unexpectedObject(id + ":name"))
            }
        }
        for child in try references(group, key: "children", id: id) {
            let value = try rawObject(child)
            let kind = try requiredString(value, key: "isa", id: child)
            switch kind {
            case "PBXGroup":
                try visitGroup(child, parent: directory)
            case "PBXFileReference":
                try visitFile(child, parent: directory)
            default:
                throw .sourceGraph(.unexpectedObject(child))
            }
        }
    }

    private mutating func visitFile(_ id: String, parent: String) throws(XcodeInputClosureError) {
        let file = try object(id, kind: "PBXFileReference")
        try visit(id)
        try fields(
            file,
            required: ["isa", "path", "sourceTree"],
            optional: ["explicitFileType", "includeInIndex", "lastKnownFileType", "name"],
            id: id
        )
        let tree = try requiredString(file, key: "sourceTree", id: id)
        let path = try requiredString(file, key: "path", id: id)
        fileTrees[id] = tree
        if let value = file["includeInIndex"] {
            let index = try value.string()
            guard index == "0" || index == "1" else {
                throw .sourceGraph(.unexpectedObject(id + ":includeInIndex"))
            }
        }
        if let value = file["name"] {
            guard !(try value.string()).isEmpty else {
                throw .sourceGraph(.unexpectedObject(id + ":name"))
            }
        }
        switch tree {
        case "BUILT_PRODUCTS_DIR":
            guard productIdentifiers.contains(id) else {
                throw .sourceGraph(.unexpectedObject(id + ":product"))
            }
        case "SDKROOT":
            guard !productIdentifiers.contains(id) else {
                throw .sourceGraph(.unexpectedObject(id + ":sdk-product"))
            }
        case "<group>", "SOURCE_ROOT", "PROJECT_DIR":
            guard !productIdentifiers.contains(id) else {
                throw .sourceGraph(.unexpectedObject(id + ":local-product"))
            }
            let base = tree == "<group>" ? parent : projectDirectory
            let kind: FileEntryKind = path.hasSuffix(".xcassets") ? .directory : .file
            localFiles[id] = try localPath(path, base: base, kind: kind)
        default:
            throw .unsafeReference(tree)
        }
    }

    private mutating func visitTarget(_ id: String) throws(XcodeInputClosureError) -> Set<String> {
        let target = try object(id, kind: "PBXNativeTarget")
        try visit(id)
        try fields(
            target,
            required: ["isa", "buildConfigurationList", "buildPhases", "name", "productName", "productReference", "productType"],
            optional: ["buildRules", "dependencies", "packageProductDependencies"],
            id: id
        )
        for key in ["buildRules", "dependencies", "packageProductDependencies"] where target[key] != nil {
            guard try references(target, key: key, id: id).isEmpty else {
                throw .sourceGraph(.unsupportedFields(id + ":" + key))
            }
        }
        let product = try requiredString(target, key: "productReference", id: id)
        guard fileTrees[product] == "BUILT_PRODUCTS_DIR" else {
            throw .sourceGraph(.missingReference(product))
        }
        let productType = try requiredString(target, key: "productType", id: id)
        guard [
            "com.apple.product-type.application",
            "com.apple.product-type.bundle.unit-test",
            "com.apple.product-type.bundle.ui-testing",
        ].contains(productType) else {
            throw .sourceGraph(.unexpectedObject(id + ":productType"))
        }
        for key in ["name", "productName"] {
            guard !(try requiredString(target, key: key, id: id)).isEmpty else {
                throw .sourceGraph(.unexpectedObject(id + ":" + key))
            }
        }
        try visitConfigurationList(try requiredString(target, key: "buildConfigurationList", id: id))
        let phases = try references(target, key: "buildPhases", id: id)
        guard !phases.isEmpty else {
            throw .sourceGraph(.missingSources(id))
        }
        var sources: Set<String> = []
        var sourcePhases = 0
        for phase in phases {
            let phaseObject = try rawObject(phase)
            let kind = try requiredString(phaseObject, key: "isa", id: phase)
            if kind == "PBXSourcesBuildPhase" {
                sourcePhases += 1
            }
            try visitPhase(phase, kind: kind, sources: &sources)
        }
        guard sourcePhases == 1, !sources.isEmpty else {
            throw .sourceGraph(.missingSources(id))
        }
        return sources
    }

    private mutating func visitPhase(
        _ id: String,
        kind: String,
        sources: inout Set<String>
    ) throws(XcodeInputClosureError) {
        guard ["PBXSourcesBuildPhase", "PBXResourcesBuildPhase", "PBXFrameworksBuildPhase"].contains(kind) else {
            throw .sourceGraph(.unexpectedObject(id + ":" + kind))
        }
        let phase = try object(id, kind: kind)
        try visit(id)
        try fields(
            phase,
            required: ["isa", "buildActionMask", "files", "runOnlyForDeploymentPostprocessing"],
            optional: [],
            id: id
        )
        guard try requiredString(phase, key: "buildActionMask", id: id) == "2147483647",
            try requiredString(phase, key: "runOnlyForDeploymentPostprocessing", id: id) == "0" else {
            throw .sourceGraph(.unexpectedObject(id + ":phase-settings"))
        }
        for buildFile in try references(phase, key: "files", id: id) {
            let value = try object(buildFile, kind: "PBXBuildFile")
            try visit(buildFile)
            try fields(value, required: ["isa", "fileRef"], optional: [], id: buildFile)
            let file = try requiredString(value, key: "fileRef", id: buildFile)
            guard let tree = fileTrees[file] else {
                throw .sourceGraph(.missingReference(file))
            }
            switch kind {
            case "PBXSourcesBuildPhase":
                guard let path = localFiles[file], path.hasSuffix(".swift"), sources.insert(path).inserted else {
                    throw .sourceGraph(.unexpectedObject(buildFile + ":source"))
                }
            case "PBXResourcesBuildPhase":
                guard localFiles[file] != nil, !fileHasSwiftPath(file) else {
                    throw .sourceGraph(.unexpectedObject(buildFile + ":resource"))
                }
            case "PBXFrameworksBuildPhase":
                guard tree == "SDKROOT" else {
                    throw .sourceGraph(.unexpectedObject(buildFile + ":framework"))
                }
            default:
                throw .sourceGraph(.unexpectedObject(id + ":phase"))
            }
        }
    }

    private mutating func visitConfigurationList(_ id: String) throws(XcodeInputClosureError) {
        let list = try object(id, kind: "XCConfigurationList")
        try visit(id)
        try fields(
            list,
            required: ["isa", "buildConfigurations", "defaultConfigurationIsVisible", "defaultConfigurationName"],
            optional: [],
            id: id
        )
        guard try requiredString(list, key: "defaultConfigurationIsVisible", id: id) == "0" else {
            throw .sourceGraph(.unexpectedObject(id + ":default-visible"))
        }
        let configurations = try references(list, key: "buildConfigurations", id: id)
        guard !configurations.isEmpty else {
            throw .sourceGraph(.unexpectedObject(id + ":configurations"))
        }
        var names: Set<String> = []
        for configuration in configurations {
            let value = try object(configuration, kind: "XCBuildConfiguration")
            try visit(configuration)
            try fields(value, required: ["isa", "buildSettings", "name"], optional: [], id: configuration)
            let name = try requiredString(value, key: "name", id: configuration)
            guard !name.isEmpty, names.insert(name).inserted else {
                throw .sourceGraph(.duplicateReference(configuration + ":name"))
            }
        }
        let selected = try requiredString(list, key: "defaultConfigurationName", id: id)
        guard names.contains(selected) else {
            throw .sourceGraph(.missingReference(id + ":default-configuration"))
        }
    }

    private func fileHasSwiftPath(_ id: String) -> Bool {
        localFiles[id]?.hasSuffix(".swift") == true
    }

    private func localPath(
        _ path: String,
        base: String,
        kind: FileEntryKind
    ) throws(XcodeInputClosureError) -> String {
        try XcodeInputClosure.validateRelativeReference(path)
        let candidate = base + "/" + path
        let observed: FileEntryKind
        do {
            observed = try FileSystemBoundary.entryKind(path: candidate)
        } catch {
            throw .sourceGraph(.missingReference(candidate))
        }
        guard observed == kind else {
            throw .unsafeReference(candidate)
        }
        let resolved = try XcodeInputClosure.contained(path: candidate, root: repositoryRoot)
        guard resolved.hasPrefix(projectDirectory + "/") else {
            throw .unsafeReference(candidate)
        }
        return resolved
    }

    private mutating func visit(_ id: String) throws(XcodeInputClosureError) {
        guard visited.insert(id).inserted else {
            throw .sourceGraph(.duplicateReference(id))
        }
    }

    private func rawObject(_ id: String) throws(XcodeInputClosureError) -> [String: OpenStepProjectValue] {
        guard let value = inspected.objects[id] else {
            throw .sourceGraph(.missingReference(id))
        }
        return try value.record()
    }

    private func object(
        _ id: String,
        kind: String
    ) throws(XcodeInputClosureError) -> [String: OpenStepProjectValue] {
        let value = try rawObject(id)
        guard try requiredString(value, key: "isa", id: id) == kind else {
            throw .sourceGraph(.unexpectedObject(id))
        }
        return value
    }

    private func requiredString(
        _ object: [String: OpenStepProjectValue],
        key: String,
        id: String
    ) throws(XcodeInputClosureError) -> String {
        guard let value = object[key] else {
            throw .sourceGraph(.missingReference(id + ":" + key))
        }
        return try value.string()
    }

    private func references(
        _ object: [String: OpenStepProjectValue],
        key: String,
        id: String
    ) throws(XcodeInputClosureError) -> [String] {
        guard let value = object[key] else {
            throw .sourceGraph(.missingReference(id + ":" + key))
        }
        let entries = try strings(value, id: id + ":" + key)
        guard Set(entries).count == entries.count else {
            throw .sourceGraph(.duplicateReference(id + ":" + key))
        }
        return entries
    }

    private func strings(
        _ value: OpenStepProjectValue,
        id: String
    ) throws(XcodeInputClosureError) -> [String] {
        let entries = try value.list()
        var names: [String] = []
        for entry in entries {
            let name = try entry.string()
            guard !name.isEmpty else {
                throw .sourceGraph(.unexpectedObject(id))
            }
            names.append(name)
        }
        return names
    }

    private func fields(
        _ object: [String: OpenStepProjectValue],
        required: Set<String>,
        optional: Set<String>,
        id: String
    ) throws(XcodeInputClosureError) {
        let actual = Set(object.keys)
        guard required.isSubset(of: actual), actual.isSubset(of: required.union(optional)) else {
            throw .sourceGraph(.unsupportedFields(id))
        }
    }
}

private indirect enum OpenStepProjectValue {
    case string(String)
    case list([OpenStepProjectValue])
    case record([String: OpenStepProjectValue])

    func string() throws(XcodeInputClosureError) -> String {
        guard case .string(let value) = self else {
            throw .invalidProjectSyntax
        }
        return value
    }

    func list() throws(XcodeInputClosureError) -> [OpenStepProjectValue] {
        guard case .list(let value) = self else {
            throw .invalidProjectSyntax
        }
        return value
    }

    func record() throws(XcodeInputClosureError) -> [String: OpenStepProjectValue] {
        guard case .record(let value) = self else {
            throw .invalidProjectSyntax
        }
        return value
    }

    func scalarStrings() throws(XcodeInputClosureError) -> [String] {
        switch self {
        case .string(let value):
            return [value]
        case .list(let values):
            var strings: [String] = []
            for value in values {
                strings.append(try value.string())
            }
            return strings
        case .record:
            throw .invalidProjectSyntax
        }
    }
}

private struct OpenStepProjectParser {
    private let bytes: [UInt8]
    private var position = 0
    private var nodes = 0

    init(data: Data) {
        self.bytes = Array(data)
    }

    mutating func parse() throws(XcodeInputClosureError) -> OpenStepProjectValue {
        guard bytes.count <= 33_554_432 else {
            throw .invalidProjectSyntax
        }
        let value = try parseValue(depth: 0)
        try skipTrivia()
        guard position == bytes.count else {
            throw .invalidProjectSyntax
        }
        return value
    }

    private mutating func parseValue(depth: Int) throws(XcodeInputClosureError) -> OpenStepProjectValue {
        guard depth < 128, nodes < 200_000 else {
            throw .invalidProjectSyntax
        }
        nodes += 1
        try skipTrivia()
        guard position < bytes.count else {
            throw .invalidProjectSyntax
        }
        switch bytes[position] {
        case 123:
            return try parseRecord(depth: depth + 1)
        case 40:
            return try parseList(depth: depth + 1)
        default:
            return .string(try parseString())
        }
    }

    private mutating func parseRecord(depth: Int) throws(XcodeInputClosureError) -> OpenStepProjectValue {
        position += 1
        var fields: [String: OpenStepProjectValue] = [:]
        while true {
            try skipTrivia()
            guard position < bytes.count else {
                throw .invalidProjectSyntax
            }
            if bytes[position] == 125 {
                position += 1
                return .record(fields)
            }
            let key = try parseString()
            try expect(61)
            let value = try parseValue(depth: depth)
            try expect(59)
            guard fields.updateValue(value, forKey: key) == nil else {
                throw .duplicateProjectKey(key)
            }
        }
    }

    private mutating func parseList(depth: Int) throws(XcodeInputClosureError) -> OpenStepProjectValue {
        position += 1
        var values: [OpenStepProjectValue] = []
        while true {
            try skipTrivia()
            guard position < bytes.count else {
                throw .invalidProjectSyntax
            }
            if bytes[position] == 41 {
                position += 1
                return .list(values)
            }
            values.append(try parseValue(depth: depth))
            try skipTrivia()
            guard position < bytes.count else {
                throw .invalidProjectSyntax
            }
            if bytes[position] == 44 {
                position += 1
            } else if bytes[position] != 41 {
                throw .invalidProjectSyntax
            }
        }
    }

    private mutating func parseString() throws(XcodeInputClosureError) -> String {
        try skipTrivia()
        guard position < bytes.count else {
            throw .invalidProjectSyntax
        }
        if bytes[position] == 34 {
            position += 1
            let start = position
            while position < bytes.count && bytes[position] != 34 {
                guard bytes[position] != 92,
                    bytes[position] != 10,
                    bytes[position] != 13 else {
                    throw .invalidProjectSyntax
                }
                position += 1
            }
            guard position < bytes.count,
                let value = String(bytes: bytes[start..<position], encoding: .utf8) else {
                throw .invalidProjectSyntax
            }
            position += 1
            return value
        }
        let start = position
        while position < bytes.count {
            let byte = bytes[position]
            if byte == 32 || byte == 9 || byte == 10 || byte == 13
                || byte == 123 || byte == 125 || byte == 40 || byte == 41
                || byte == 61 || byte == 59 || byte == 44 || byte == 34
                || (byte == 47 && position + 1 < bytes.count
                    && (bytes[position + 1] == 47 || bytes[position + 1] == 42)) {
                break
            }
            position += 1
        }
        guard position > start,
            let value = String(bytes: bytes[start..<position], encoding: .utf8) else {
            throw .invalidProjectSyntax
        }
        return value
    }

    private mutating func expect(_ expected: UInt8) throws(XcodeInputClosureError) {
        try skipTrivia()
        guard position < bytes.count, bytes[position] == expected else {
            throw .invalidProjectSyntax
        }
        position += 1
    }

    private mutating func skipTrivia() throws(XcodeInputClosureError) {
        while position < bytes.count {
            let byte = bytes[position]
            if byte == 32 || byte == 9 || byte == 10 || byte == 13 {
                position += 1
                continue
            }
            if byte == 47 && position + 1 < bytes.count && bytes[position + 1] == 47 {
                position += 2
                while position < bytes.count && bytes[position] != 10 {
                    position += 1
                }
                continue
            }
            if byte == 47 && position + 1 < bytes.count && bytes[position + 1] == 42 {
                position += 2
                var ended = false
                while position + 1 < bytes.count {
                    if bytes[position] == 42 && bytes[position + 1] == 47 {
                        position += 2
                        ended = true
                        break
                    }
                    position += 1
                }
                guard ended else {
                    throw .invalidProjectSyntax
                }
                continue
            }
            return
        }
    }
}
