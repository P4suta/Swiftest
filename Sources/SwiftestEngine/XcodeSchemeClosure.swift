import Foundation
import SwiftestPlatform

struct XcodeVerifiedPlan: Equatable, Sendable {
    let planName: String
    let configurationName: String
    let buildConfiguration: XcodeBuildConfiguration
    let targets: [XcodeVerifiedTarget]
    let compiledSources: XcodeCompiledSourceSet
}

enum XcodeSchemeClosure {
    static func verify(
        scheme: String,
        container: XcodeContainer,
        projects: [XcodeVerifiedProject],
        repositoryRoot: String
    ) throws(XcodeInputClosureError) -> XcodeVerifiedPlan {
        try XcodeInputClosure.validateRelativeReference(scheme)
        guard !scheme.contains("/") else {
            throw .invalidScheme
        }
        let projectPaths = Set(projects.map(\.path))
        let containers = Set([container.path] + projects.map(\.path)).sorted()
        var locations: [(path: String, base: String)] = []
        for candidate in containers {
            try rejectConflictingUserScheme(name: scheme + ".xcscheme", container: candidate)
            let directory = candidate + "/xcshareddata/xcschemes"
            let listing: OptionalDirectoryListing
            do {
                listing = try FileSystemBoundary.listIfPresent(path: directory)
            } catch let error {
                throw .platform(error)
            }
            let entries: [String]
            switch listing {
            case .absent:
                continue
            case .entries(let found):
                entries = found
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
        let inspection = try inspectScheme(data)
        try validateReferences(
            inspection.references,
            base: location.base,
            projects: projectPaths,
            repositoryRoot: repositoryRoot
        )
        guard let planReference = inspection.testPlanReference else {
            throw .unsupportedSchemeFeature("test-plan-required")
        }
        let planPath = try XcodeInputClosure.contained(
            path: location.base + "/" + planReference,
            root: repositoryRoot
        )
        let planKind: FileEntryKind
        do {
            planKind = try FileSystemBoundary.entryKind(path: planPath)
        } catch let error {
            throw .platform(error)
        }
        guard planKind == .file else {
            throw .invalidTestPlan("file")
        }
        let planData: Data
        do {
            planData = try FileSystemBoundary.read(path: planPath)
        } catch let error {
            throw .platform(error)
        }
        let plan = try XcodeTestPlanClosure.decode(planData)
        try validateReferences(
            plan.targets.map(\.project),
            base: location.base,
            projects: projectPaths,
            repositoryRoot: repositoryRoot
        )
        let compiledSources = try validatePlanTargets(
            plan.targets,
            base: location.base,
            projects: projects,
            repositoryRoot: repositoryRoot
        )
        guard inspection.buildTargets == plan.targets,
            let buildConfiguration = inspection.buildConfiguration else {
            throw .invalidTestPlan("scheme-build-target")
        }
        let planName = URL(fileURLWithPath: planReference).deletingPathExtension().lastPathComponent
        guard !planName.isEmpty else {
            throw .invalidTestPlan("name")
        }
        return XcodeVerifiedPlan(
            planName: planName,
            configurationName: plan.configurationName,
            buildConfiguration: buildConfiguration,
            targets: plan.targets,
            compiledSources: compiledSources
        )
    }

    static func validatePlanTargets(
        _ targets: [XcodeVerifiedTarget],
        base: String,
        projects: [XcodeVerifiedProject],
        repositoryRoot: String
    ) throws(XcodeInputClosureError) -> XcodeCompiledSourceSet {
        guard targets.count == 1, let target = targets.first else {
            throw .invalidTestPlan("target-count")
        }
        let projectPath = try XcodeInputClosure.contained(
            path: base + "/" + target.project,
            root: repositoryRoot
        )
        let matchingProjects = projects.filter { $0.path == projectPath }
        guard matchingProjects.count == 1, let project = matchingProjects.first,
            project.targetIdentifiers.contains(target.identifier),
            let sources = project.sourcePathsByTarget[target.identifier],
            !sources.isEmpty else {
            throw .invalidTestPlan("target-identifier")
        }
        do {
            return try XcodeCompiledSourceSet.capture(sources.sorted(), repositoryRoot: repositoryRoot)
        } catch {
            throw .invalidTestPlan("compiled-sources")
        }
    }

    private static func rejectConflictingUserScheme(
        name: String,
        container: String
    ) throws(XcodeInputClosureError) {
        let listing: OptionalDirectoryListing
        do {
            listing = try FileSystemBoundary.listIfPresent(path: container + "/xcuserdata")
        } catch let error {
            throw .platform(error)
        }
        let users: [String]
        switch listing {
        case .absent:
            return
        case .entries(let found):
            users = found
        }
        for user in users {
            let directory = container + "/xcuserdata/" + user + "/xcschemes"
            let userListing: OptionalDirectoryListing
            do {
                userListing = try FileSystemBoundary.listIfPresent(path: directory)
            } catch let error {
                throw .platform(error)
            }
            let entries: [String]
            switch userListing {
            case .absent:
                continue
            case .entries(let found):
                entries = found
            }
            if entries.contains(name) {
                throw .ambiguousScheme
            }
        }
    }

    static func inspect(_ data: Data) throws(XcodeInputClosureError) -> [String] {
        try inspectScheme(data).references
    }

    private static func inspectScheme(_ data: Data) throws(XcodeInputClosureError) -> SchemeInspection {
        let document: XcodeXMLNode
        do {
            document = try XcodeXML.parse(data, maximumBytes: 2_097_152)
        } catch {
            throw .invalidScheme
        }
        var inspection = SchemeInspection()
        try inspect(document, parent: nil, inspection: &inspection)
        guard inspection.buildForTestingCount == 1,
            inspection.testableCount > 0 || inspection.testPlanReference != nil else {
            throw .invalidScheme
        }
        return inspection
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
                version == "1.3",
                node.attributes["wasCreatedForAppExtension"] == nil else {
                throw .invalidScheme
            }
        case .buildAction:
            guard keys == element.allowedAttributes,
                node.attributes["parallelizeBuildables"] == "NO",
                node.attributes["buildImplicitDependencies"] == "NO" else {
                throw .unsupportedSchemeFeature("build-action-settings")
            }
        case .buildActionEntry:
            guard keys == element.allowedAttributes,
                node.attributes["buildForTesting"] == "YES",
                node.attributes["buildForRunning"] == "NO",
                node.attributes["buildForProfiling"] == "NO",
                node.attributes["buildForArchiving"] == "NO",
                node.attributes["buildForAnalyzing"] == "NO" else {
                throw .unsupportedSchemeFeature("build-entry-settings")
            }
            inspection.buildForTestingCount += 1
        case .testAction:
            guard let configuration = node.attributes["buildConfiguration"],
                let buildConfiguration = XcodeBuildConfiguration(rawValue: configuration),
                node.attributes["shouldUseLaunchSchemeArgsEnv"] == "NO" else {
                throw .invalidScheme
            }
            inspection.buildConfiguration = buildConfiguration
            for key in ["enableAddressSanitizer", "enableThreadSanitizer", "enableUBSanitizer",
                "onlyGenerateCoverageForSpecifiedTargets"] where node.attributes[key] != nil {
                guard node.attributes[key] == "NO" else {
                    throw .unsupportedSchemeFeature(key)
                }
            }
            if let coverage = node.attributes["codeCoverageEnabled"], coverage != "YES" {
                throw .unsupportedSchemeFeature("codeCoverageEnabled")
            }
            if node.attributes["selectedDebuggerIdentifier"] != nil
                || node.attributes["selectedLauncherIdentifier"] != nil {
                throw .unsupportedSchemeFeature("test-launcher")
            }
        case .testableReference:
            guard node.attributes["skipped"] == "NO",
                node.attributes["parallelizable"] == nil
                    || node.attributes["parallelizable"] == "NO" else {
                throw .unsupportedSchemeFeature("skipped-test")
            }
            inspection.testableCount += 1
        case .testPlanReference:
            guard keys == element.allowedAttributes,
                node.attributes["default"] == "YES",
                let location = node.attributes["reference"],
                location.hasPrefix("container:") else {
                throw .invalidScheme
            }
            let reference = String(location.dropFirst("container:".count))
            guard reference.hasSuffix(".xctestplan") else {
                throw .unsupportedSchemeFeature("test-plan-reference")
            }
            try XcodeInputClosure.validateRelativeReference(reference)
            inspection.testPlanReference = reference
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
            if parent == .buildActionEntry {
                guard let name = node.attributes["BlueprintName"], !name.isEmpty,
                    node.attributes["BuildableName"] == name + ".xctest" else {
                    throw .invalidScheme
                }
                inspection.buildTargets.append(XcodeVerifiedTarget(
                    project: reference,
                    identifier: identifier,
                    name: name
                ))
            }
        case .launchAction, .profileAction:
            if let workingDirectory = node.attributes["useCustomWorkingDirectory"],
                workingDirectory != "NO" {
                throw .unsupportedSchemeFeature("custom-working-directory")
            }
            throw .unsupportedSchemeFeature(node.name)
        case .analyzeAction, .archiveAction, .macroExpansion:
            throw .unsupportedSchemeFeature(node.name)
        case .buildActionEntries, .testables, .testPlans,
            .buildableProductRunnable:
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
        if element == .testAction,
            actual.contains(.testables) == actual.contains(.testPlans) {
            throw .invalidScheme
        }
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
    var buildTargets: [XcodeVerifiedTarget] = []
    var buildForTestingCount = 0
    var testableCount = 0
    var testPlanReference: String?
    var buildConfiguration: XcodeBuildConfiguration?
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
    case testPlans = "TestPlans"
    case testPlanReference = "TestPlanReference"
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
            return []
        case .testables:
            return [.testableReference]
        case .testPlans:
            return [.testPlanReference]
        case .launchAction, .profileAction, .analyzeAction, .archiveAction, .buildableReference:
            return []
        case .testPlanReference:
            return []
        }
    }

    var repeatableChildren: Set<SchemeElement> {
        switch self {
        case .buildActionEntries:
            return []
        case .testables:
            return [.testableReference]
        case .scheme, .buildAction, .buildActionEntry, .buildableReference, .testAction,
            .testableReference, .launchAction, .buildableProductRunnable, .profileAction,
            .analyzeAction, .archiveAction, .macroExpansion, .testPlans, .testPlanReference:
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
            return [.testables, .testPlans, .macroExpansion]
        case .launchAction, .profileAction:
            return [.buildableProductRunnable, .macroExpansion]
        case .buildAction, .buildActionEntries, .buildActionEntry, .buildableReference,
            .testables, .testableReference, .testPlans, .testPlanReference,
            .buildableProductRunnable, .analyzeAction,
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
        case .buildActionEntries, .testables, .testPlans, .macroExpansion:
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
        case .testPlanReference:
            return ["default", "reference"]
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
