import Foundation
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
}

enum XcodeInputClosure {
    static func verify(
        container: XcodeContainer,
        repositoryRoot: String,
        scheme: String
    ) throws(XcodeInputClosureError) {
        let root = URL(fileURLWithPath: repositoryRoot).standardizedFileURL.resolvingSymlinksInPath().path
        guard !root.isEmpty else {
            throw .externalContainer(repositoryRoot)
        }
        let projects: [String]
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
            var verified: [String] = []
            for reference in references {
                let project = parent + "/" + reference
                verified.append(try verifyProject(path: project, root: root))
            }
            projects = verified
        }
        try XcodeSchemeClosure.verify(
            scheme: scheme,
            container: container,
            projects: projects,
            repositoryRoot: root
        )
    }

    static func inspectProject(_ data: Data) throws(XcodeInputClosureError) {
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

    private static func verifyProject(path: String, root: String) throws(XcodeInputClosureError) -> String {
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
        try inspectProject(data)
        return project
    }

    static func contained(path: String, root: String) throws(XcodeInputClosureError) -> String {
        let resolved = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
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
