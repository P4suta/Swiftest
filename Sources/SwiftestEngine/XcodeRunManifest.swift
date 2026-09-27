import Foundation
import SwiftestCodec
import SwiftestPlatform

public enum XcodeRunManifestError: Error, Equatable, Sendable {
    case codec(StrictJSONError)
    case platform(PlatformError)
    case inputClosure(XcodeInputClosureError)
    case unsupportedShape(String)
    case invalidValue(String)
    case sourceOutsideRepository(String)
    case duplicateSource(String)
    case sourceSetMismatch
}

struct XcodeRunManifest: Equatable, Sendable {
    let planName: String
    let configurationName: String
    let targetName: String
    let targetIdentifier: String
    let sourceFiles: [String]

    private init(
        planName: String,
        configurationName: String,
        targetName: String,
        targetIdentifier: String,
        sourceFiles: [String]
    ) {
        self.planName = planName
        self.configurationName = configurationName
        self.targetName = targetName
        self.targetIdentifier = targetIdentifier
        self.sourceFiles = sourceFiles
    }

    static func decode(
        _ data: Data,
        verifiedPlan: XcodeVerifiedPlan,
        scheme: String,
        container: XcodeContainer,
        repositoryRoot: String
    ) throws(XcodeRunManifestError) -> XcodeRunManifest {
        let document: JSONValue
        do {
            document = try StrictJSON.decode(data)
        } catch let error {
            throw .codec(error)
        }
        guard verifiedPlan.targets.count == 1 else {
            throw .unsupportedShape("test-targets")
        }
        let target = verifiedPlan.targets[0]
        var root = try fields(document)
        let metadata = try object(&root, "__xctestrun_metadata__")
        let coverage = try array(&root, "CodeCoverageBuildableInfos")
        let containerInfo = try object(&root, "ContainerInfo")
        let plan = try object(&root, "TestPlan")
        let configurations = try array(&root, "TestConfigurations")
        try finish(root)

        var metadataReader = try fields(metadata)
        try expectInteger(&metadataReader, "FormatVersion", 2)
        try finish(metadataReader)

        let containerName = URL(fileURLWithPath: container.path).deletingPathExtension().lastPathComponent
        var containerReader = try fields(containerInfo)
        try expectString(&containerReader, "ContainerName", containerName)
        try expectString(&containerReader, "SchemeName", scheme)
        try finish(containerReader)

        var planReader = try fields(plan)
        try expectBoolean(&planReader, "IsDefault", true)
        try expectString(&planReader, "Name", verifiedPlan.planName)
        try finish(planReader)

        guard configurations.count == 1, coverage.count == 1 else {
            throw .unsupportedShape("configuration-or-coverage")
        }
        var configurationReader = try fields(configurations[0])
        try expectBoolean(&configurationReader, "IsEnabled", true)
        try expectString(&configurationReader, "Name", verifiedPlan.configurationName)
        let testTargets = try array(&configurationReader, "TestTargets")
        try finish(configurationReader)
        guard testTargets.count == 1 else {
            throw .unsupportedShape("test-targets")
        }

        let product = try decodeTarget(
            testTargets[0],
            target: target,
            scheme: scheme,
            planName: verifiedPlan.planName,
            buildConfiguration: verifiedPlan.buildConfiguration
        )
        let compiledSources = try decodeCoverage(
            coverage[0],
            target: target,
            product: product,
            repositoryRoot: repositoryRoot
        )
        guard compiledSources == verifiedPlan.compiledSources else {
            throw .sourceSetMismatch
        }
        return XcodeRunManifest(
            planName: verifiedPlan.planName,
            configurationName: verifiedPlan.configurationName,
            targetName: target.name,
            targetIdentifier: target.identifier,
            sourceFiles: compiledSources.sortedPaths
        )
    }

    private struct Product {
        let bundlePath: String
        let moduleName: String
    }

    private static func decodeTarget(
        _ input: JSONValue,
        target: XcodeVerifiedTarget,
        scheme: String,
        planName: String,
        buildConfiguration: XcodeBuildConfiguration
    ) throws(XcodeRunManifestError) -> Product {
        guard !target.name.contains("/"), !target.name.contains("\\"),
            !target.name.contains(":"), !target.name.isEmpty else {
            throw .invalidValue("target-name")
        }
        let projectName = URL(fileURLWithPath: target.project).deletingPathExtension().lastPathComponent
        var reader = try fields(input)
        try expectString(&reader, "BlueprintName", target.name)
        try expectString(&reader, "BlueprintProviderName", projectName)
        try expectString(&reader, "BlueprintProviderRelativePath", target.project)
        try expectEmptyArray(&reader, "CommandLineArguments")
        try expectInteger(&reader, "DefaultTestExecutionTimeAllowance", 600)
        try expectInteger(&reader, "DiagnosticCollectionPolicy", 1)
        let dependencies = try array(&reader, "DependentProductPaths")
        let environment = try object(&reader, "EnvironmentVariables")
        try expectBoolean(&reader, "IsMemoryTaggingAddressSanitizerEnabled", false)
        try expectString(&reader, "PreferredScreenCaptureFormat", "screenRecording")
        let moduleName = try string(&reader, "ProductModuleName")
        try expectString(&reader, "SystemAttachmentLifetime", "deleteOnSuccess")
        let bundlePath = try string(&reader, "TestBundlePath")
        let host = try string(&reader, "TestHostPath")
        try expectString(&reader, "TestLanguage", "")
        try expectString(&reader, "TestRegion", "")
        try expectBoolean(&reader, "TestTimeoutsEnabled", false)
        let testingEnvironment = try object(&reader, "TestingEnvironmentVariables")
        try expectEmptyArray(&reader, "ToolchainsSettingValue")
        try expectString(&reader, "UserAttachmentLifetime", "deleteOnSuccess")
        try expectString(&reader, "ClangProfileDataDirectoryPath", "__DERIVEDDATA__/Build/ProfileData")
        try finish(reader)

        guard moduleName == target.name,
            bundlePath == "__TESTROOT__/" + buildConfiguration.rawValue + "/" + target.name + ".xctest",
            dependencies == [.string(bundlePath)],
            host == "__PLATFORMS__/MacOSX.platform/Developer/Library/Xcode/Agents/xctest" else {
            throw .invalidValue("test-product")
        }
        try expectStrings(environment, [
            "APP_DISTRIBUTOR_ID_OVERRIDE": "com.apple.AppStore",
            "DYLD_INSERT_LIBRARIES": "/usr/lib/libRPAC.dylib",
            "IDE_CHOSEN_LOGGING_METHOD": "1",
            "OS_ACTIVITY_DT_MODE": "YES",
            "PERFC_ENABLE_EXTENDED_DIAGNOSTIC_FORMAT": "1",
            "PERFC_ENABLE_PROFILE_MODE": "1",
            "PERFC_RESET_INSERT_LIBRARIES": "1",
            "PERFC_SUPPRESS_SYSTEM_REPORTS": "1",
            "SQLITE_ENABLE_THREAD_ASSERTIONS": "1",
            "TERM": "dumb",
        ])
        let configuration = buildConfiguration.rawValue
        try expectStrings(testingEnvironment, [
            "DYLD_FRAMEWORK_PATH": "__TESTROOT__/" + configuration
                + ":__SHAREDFRAMEWORKS__:__PLATFORMS__/MacOSX.platform/Developer/Library/Frameworks",
            "DYLD_INSERT_LIBRARIES": "__DEVELOPERUSRLIB__/libMainThreadChecker.dylib:/usr/lib/libRPAC.dylib",
            "DYLD_LIBRARY_PATH": "__TESTROOT__/" + configuration
                + ":__PLATFORMS__/MacOSX.platform/Developer/usr/lib",
            "PERFC_SUPPRESS_SYSTEM_REPORTS": "1",
            "XCODE_SCHEME_NAME": scheme,
            "XCODE_TEST_PLAN_NAME": planName,
            "__XCODE_BUILT_PRODUCTS_DIR_PATHS": "__TESTROOT__/" + configuration,
            "__XPC_DYLD_FRAMEWORK_PATH": "__TESTROOT__/" + configuration,
            "__XPC_DYLD_LIBRARY_PATH": "__TESTROOT__/" + configuration,
        ])
        return Product(bundlePath: bundlePath, moduleName: moduleName)
    }

    private static func decodeCoverage(
        _ input: JSONValue,
        target: XcodeVerifiedTarget,
        product: Product,
        repositoryRoot: String
    ) throws(XcodeRunManifestError) -> XcodeCompiledSourceSet {
        var reader = try fields(input)
        let architectures = try array(&reader, "Architectures")
        try expectString(&reader, "BuildableIdentifier", target.identifier + ":primary")
        try expectBoolean(&reader, "IncludeInReport", true)
        try expectBoolean(&reader, "IsStatic", false)
        try expectString(&reader, "Name", target.name + ".xctest")
        let productPaths = try array(&reader, "ProductPaths")
        let sourceValues = try array(&reader, "SourceFiles")
        let toolchains = try array(&reader, "Toolchains")
        try finish(reader)
        var seenArchitectures: Set<String> = []
        for architecture in architectures {
            guard case .string(let name) = architecture,
                ["arm64", "arm64e", "x86_64"].contains(name),
                seenArchitectures.insert(name).inserted else {
                throw .invalidValue("Architectures")
            }
        }
        guard !seenArchitectures.isEmpty,
            productPaths == [.string(product.bundlePath + "/Contents/MacOS/" + product.moduleName)],
            toolchains == [.string("com.apple.dt.toolchain.XcodeDefault")],
            !sourceValues.isEmpty else {
            throw .invalidValue("coverage-buildable")
        }
        var sources: [String] = []
        for value in sourceValues {
            guard case .string(let path) = value else {
                throw .invalidValue("SourceFiles")
            }
            sources.append(path)
        }
        do {
            return try XcodeCompiledSourceSet.capture(sources, repositoryRoot: repositoryRoot)
        } catch let error {
            switch error {
            case .invalidRoot(let path):
                throw .platform(.invalidRoot(path))
            case .empty, .invalidSource:
                throw .invalidValue("SourceFiles")
            case .unreadableSource(let path):
                throw .platform(.read(path))
            case .outsideRepository(let path):
                throw .sourceOutsideRepository(path)
            case .duplicateSource(let path):
                throw .duplicateSource(path)
            }
        }
    }

    private static func expectStrings(
        _ input: JSONValue,
        _ expected: [String: String]
    ) throws(XcodeRunManifestError) {
        var reader = try fields(input)
        for key in expected.keys.sorted() {
            guard let value = expected[key] else {
                throw .invalidValue(key)
            }
            try expectString(&reader, key, value)
        }
        try finish(reader)
    }

    private static func fields(_ input: JSONValue) throws(XcodeRunManifestError) -> JSONObjectReader {
        do {
            return try JSONObjectReader(input)
        } catch let error {
            throw .codec(error)
        }
    }

    private static func object(
        _ reader: inout JSONObjectReader,
        _ key: String
    ) throws(XcodeRunManifestError) -> JSONValue {
        let input = try value(&reader, key)
        guard case .object = input else {
            throw .codec(.expectedObject)
        }
        return input
    }

    private static func value(
        _ reader: inout JSONObjectReader,
        _ key: String
    ) throws(XcodeRunManifestError) -> JSONValue {
        do {
            return try reader.requiredValue(key)
        } catch let error {
            throw .codec(error)
        }
    }

    private static func array(
        _ reader: inout JSONObjectReader,
        _ key: String
    ) throws(XcodeRunManifestError) -> [JSONValue] {
        do {
            return try reader.requiredArray(key)
        } catch let error {
            throw .codec(error)
        }
    }

    private static func string(
        _ reader: inout JSONObjectReader,
        _ key: String
    ) throws(XcodeRunManifestError) -> String {
        do {
            return try reader.requiredString(key)
        } catch let error {
            throw .codec(error)
        }
    }

    private static func expectString(
        _ reader: inout JSONObjectReader,
        _ key: String,
        _ expected: String
    ) throws(XcodeRunManifestError) {
        guard try string(&reader, key) == expected else {
            throw .invalidValue(key)
        }
    }

    private static func expectBoolean(
        _ reader: inout JSONObjectReader,
        _ key: String,
        _ expected: Bool
    ) throws(XcodeRunManifestError) {
        let actual: Bool
        do {
            actual = try reader.requiredBoolean(key)
        } catch let error {
            throw .codec(error)
        }
        guard actual == expected else {
            throw .invalidValue(key)
        }
    }

    private static func expectInteger(
        _ reader: inout JSONObjectReader,
        _ key: String,
        _ expected: Int
    ) throws(XcodeRunManifestError) {
        let actual: Int
        do {
            actual = try reader.requiredInteger(key)
        } catch let error {
            throw .codec(error)
        }
        guard actual == expected else {
            throw .invalidValue(key)
        }
    }

    private static func expectEmptyArray(
        _ reader: inout JSONObjectReader,
        _ key: String
    ) throws(XcodeRunManifestError) {
        guard try array(&reader, key).isEmpty else {
            throw .invalidValue(key)
        }
    }

    private static func finish(_ reader: JSONObjectReader) throws(XcodeRunManifestError) {
        do {
            try reader.finish()
        } catch let error {
            throw .codec(error)
        }
    }
}
