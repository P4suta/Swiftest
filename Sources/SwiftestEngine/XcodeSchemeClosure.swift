import Foundation
import SwiftestPlatform

enum XcodeSchemeClosure {
    static func verify(
        scheme: String,
        container: XcodeContainer,
        projects: [String],
        repositoryRoot: String
    ) throws(XcodeInputClosureError) {
        try XcodeInputClosure.validateRelativeReference(scheme)
        guard !scheme.contains("/") else {
            throw .invalidScheme
        }
        let containers = Set([container.path] + projects).sorted()
        var locations: [(path: String, base: String)] = []
        for candidate in containers {
            try rejectConflictingUserScheme(name: scheme + ".xcscheme", container: candidate)
            let directory = candidate + "/xcshareddata/xcschemes"
            let entries: [String]
            do {
                entries = try FileSystemBoundary.list(path: directory)
            } catch {
                continue
            }
            let name = scheme + ".xcscheme"
            if entries.contains(name) {
                let base = URL(fileURLWithPath: candidate).deletingLastPathComponent().path
                locations.append((directory + "/" + name, base))
            }
        }
        guard locations.count == 1, let location = locations.first else {
            if locations.isEmpty {
                throw .invalidScheme
            }
            throw .ambiguousScheme
        }
        let schemePath = try XcodeInputClosure.contained(path: location.path, root: repositoryRoot)
        let kind: FileEntryKind
        do {
            kind = try FileSystemBoundary.entryKind(path: schemePath)
        } catch let error {
            throw .platform(error)
        }
        guard kind == .file else {
            throw .invalidScheme
        }
        let data: Data
        do {
            data = try FileSystemBoundary.read(path: schemePath)
        } catch let error {
            throw .platform(error)
        }
        let references = try inspect(data)
        try validateReferences(
            references,
            base: location.base,
            projects: Set(projects),
            repositoryRoot: repositoryRoot
        )
    }

    private static func rejectConflictingUserScheme(
        name: String,
        container: String
    ) throws(XcodeInputClosureError) {
        let users: [String]
        do {
            users = try FileSystemBoundary.list(path: container + "/xcuserdata")
        } catch {
            return
        }
        for user in users {
            let directory = container + "/xcuserdata/" + user + "/xcschemes"
            let entries: [String]
            do {
                entries = try FileSystemBoundary.list(path: directory)
            } catch {
                continue
            }
            if entries.contains(name) {
                throw .ambiguousScheme
            }
        }
    }

    static func inspect(_ data: Data) throws(XcodeInputClosureError) -> [String] {
        let document: XcodeXMLNode
        do {
            document = try XcodeXML.parse(data, maximumBytes: 2_097_152)
        } catch {
            throw .invalidScheme
        }
        var inspection = SchemeInspection()
        try inspect(document, parent: nil, inspection: &inspection)
        guard inspection.buildForTestingCount > 0,
            inspection.testableCount > 0 else {
            throw .invalidScheme
        }
        return inspection.references
    }

    static func validateReferences(
        _ references: [String],
        base: String,
        projects: Set<String>,
        repositoryRoot: String
    ) throws(XcodeInputClosureError) {
        for reference in references {
            let path = base + "/" + reference
            let contained = try XcodeInputClosure.contained(path: path, root: repositoryRoot)
            guard projects.contains(contained) else {
                throw .externalContainer(reference)
            }
        }
    }

    private static func inspect(
        _ node: XcodeXMLNode,
        parent: SchemeElement?,
        inspection: inout SchemeInspection
    ) throws(XcodeInputClosureError) {
        guard let element = SchemeElement(rawValue: node.name) else {
            throw .unsupportedSchemeFeature(node.name)
        }
        if let parent {
            guard parent.allowedChildren.contains(element) else {
                throw .unsupportedSchemeFeature(node.name)
            }
        } else if element != .scheme {
            throw .unsupportedSchemeFeature(node.name)
        }
        let keys = Set(node.attributes.keys)
        guard keys.isSubset(of: element.allowedAttributes) else {
            throw .unsupportedSchemeFeature(node.name + "-attributes")
        }
        for value in node.attributes.values {
            if value.contains("$") || value.contains("../") || value.hasPrefix("/") {
                throw .unsupportedSchemeFeature(node.name + "-dynamic-attribute")
            }
        }
        switch element {
        case .scheme:
            guard let version = node.attributes["version"],
                !version.isEmpty,
                version.allSatisfy({ $0.isNumber || $0 == "." }) else {
                throw .invalidScheme
            }
        case .buildActionEntry:
            if node.attributes["buildForTesting"] == "YES" {
                inspection.buildForTestingCount += 1
            }
        case .testAction:
            guard let configuration = node.attributes["buildConfiguration"],
                !configuration.isEmpty else {
                throw .invalidScheme
            }
        case .testableReference:
            guard node.attributes["skipped"] == "NO" else {
                throw .unsupportedSchemeFeature("skipped-test")
            }
            inspection.testableCount += 1
        case .launchAction, .profileAction:
            if let workingDirectory = node.attributes["useCustomWorkingDirectory"],
                workingDirectory != "NO" {
                throw .unsupportedSchemeFeature("custom-working-directory")
            }
        case .buildableReference:
            guard keys == SchemeElement.buildableReference.allowedAttributes,
                node.attributes["BuildableIdentifier"] == "primary",
                let identifier = node.attributes["BlueprintIdentifier"],
                !identifier.isEmpty,
                let location = node.attributes["ReferencedContainer"],
                location.hasPrefix("container:") else {
                throw .invalidScheme
            }
            let reference = String(location.dropFirst("container:".count))
            guard reference.hasSuffix(".xcodeproj") else {
                throw .externalContainer(reference)
            }
            try XcodeInputClosure.validateRelativeReference(reference)
            inspection.references.append(reference)
        case .buildAction, .buildActionEntries, .testables,
            .buildableProductRunnable, .analyzeAction, .archiveAction, .macroExpansion:
            break
        }
        var children: [SchemeElement] = []
        for child in node.children {
            guard let kind = SchemeElement(rawValue: child.name),
                element.allowedChildren.contains(kind) else {
                throw .unsupportedSchemeFeature(child.name)
            }
            children.append(kind)
            try inspect(child, parent: element, inspection: &inspection)
        }
        try validateChildren(children, of: element)
    }

    private static func validateChildren(
        _ children: [SchemeElement],
        of element: SchemeElement
    ) throws(XcodeInputClosureError) {
        let actual = Set(children)
        guard element.requiredChildren.isSubset(of: actual) else {
            throw .invalidScheme
        }
        for kind in actual where !element.repeatableChildren.contains(kind) {
            if children.filter({ $0 == kind }).count != 1 {
                throw .invalidScheme
            }
        }
    }
}

private struct SchemeInspection {
    var references: [String] = []
    var buildForTestingCount = 0
    var testableCount = 0
}

private enum SchemeElement: String {
    case scheme = "Scheme"
    case buildAction = "BuildAction"
    case buildActionEntries = "BuildActionEntries"
    case buildActionEntry = "BuildActionEntry"
    case buildableReference = "BuildableReference"
    case testAction = "TestAction"
    case testables = "Testables"
    case testableReference = "TestableReference"
    case launchAction = "LaunchAction"
    case buildableProductRunnable = "BuildableProductRunnable"
    case profileAction = "ProfileAction"
    case analyzeAction = "AnalyzeAction"
    case archiveAction = "ArchiveAction"
    case macroExpansion = "MacroExpansion"

    var requiredChildren: Set<SchemeElement> {
        switch self {
        case .scheme:
            return [.buildAction, .testAction]
        case .buildAction:
            return [.buildActionEntries]
        case .buildActionEntries:
            return [.buildActionEntry]
        case .buildActionEntry, .testableReference, .buildableProductRunnable, .macroExpansion:
            return [.buildableReference]
        case .testAction:
            return [.testables]
        case .testables:
            return [.testableReference]
        case .launchAction, .profileAction, .analyzeAction, .archiveAction, .buildableReference:
            return []
        }
    }

    var repeatableChildren: Set<SchemeElement> {
        switch self {
        case .buildActionEntries:
            return [.buildActionEntry]
        case .testables:
            return [.testableReference]
        case .scheme, .buildAction, .buildActionEntry, .buildableReference, .testAction,
            .testableReference, .launchAction, .buildableProductRunnable, .profileAction,
            .analyzeAction, .archiveAction, .macroExpansion:
            return []
        }
    }

    var allowedChildren: Set<SchemeElement> {
        requiredChildren.union(optionalChildren)
    }

    var optionalChildren: Set<SchemeElement> {
        switch self {
        case .scheme:
            return [.launchAction, .profileAction, .analyzeAction, .archiveAction]
        case .testAction:
            return [.macroExpansion]
        case .launchAction, .profileAction:
            return [.buildableProductRunnable, .macroExpansion]
        case .buildAction, .buildActionEntries, .buildActionEntry, .buildableReference,
            .testables, .testableReference, .buildableProductRunnable, .analyzeAction,
            .archiveAction, .macroExpansion:
            return []
        }
    }

    var allowedAttributes: Set<String> {
        switch self {
        case .scheme:
            return ["LastUpgradeVersion", "version", "wasCreatedForAppExtension"]
        case .buildAction:
            return ["parallelizeBuildables", "buildImplicitDependencies"]
        case .buildActionEntries, .testables, .macroExpansion:
            return []
        case .buildActionEntry:
            return ["buildForTesting", "buildForRunning", "buildForProfiling", "buildForArchiving", "buildForAnalyzing"]
        case .buildableReference:
            return ["BuildableIdentifier", "BlueprintIdentifier", "BuildableName", "BlueprintName", "ReferencedContainer"]
        case .testAction:
            return ["buildConfiguration", "selectedDebuggerIdentifier", "selectedLauncherIdentifier",
                "shouldUseLaunchSchemeArgsEnv", "codeCoverageEnabled",
                "onlyGenerateCoverageForSpecifiedTargets", "enableAddressSanitizer",
                "enableThreadSanitizer", "enableUBSanitizer"]
        case .testableReference:
            return ["skipped", "parallelizable"]
        case .launchAction:
            return ["buildConfiguration", "selectedDebuggerIdentifier", "selectedLauncherIdentifier",
                "launchStyle", "useCustomWorkingDirectory", "ignoresPersistentStateOnLaunch",
                "debugDocumentVersioning", "debugServiceExtension", "allowLocationSimulation"]
        case .buildableProductRunnable:
            return ["runnableDebuggingMode"]
        case .profileAction:
            return ["buildConfiguration", "shouldUseLaunchSchemeArgsEnv", "savedToolIdentifier",
                "useCustomWorkingDirectory", "debugDocumentVersioning"]
        case .analyzeAction:
            return ["buildConfiguration"]
        case .archiveAction:
            return ["buildConfiguration", "revealArchiveInOrganizer"]
        }
    }
}
