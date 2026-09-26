import Foundation
@testable import SwiftestLaws
import SwiftestModel
import SwiftestPlatform
import Testing

@Test
func everyLawHasExactlyOneLegalAndIllegalFixture() {
    #expect(LawFixtureCatalog.all.count == LawCode.allCases.count)
    #expect(Set(LawFixtureCatalog.all.map(\.law)) == Set(LawCode.allCases))
    for fixture in LawFixtureCatalog.all {
        #expect(!fixture.legal.isEmpty)
        #expect(!fixture.illegal.isEmpty)
        #expect(fixture.legal != fixture.illegal)
    }
}

@Test
func syntacticLawFixturesDetectOnlyIllegalForms() {
    let syntactic: Set<LawCode> = [
        .forbiddenComment,
        .unreadableSource,
        .prohibitedTry,
        .forceUnwrap,
        .forceCast,
        .stringError,
        .ignoredResult,
        .semanticDefault,
        .optionalBoolean,
        .policyBoolean,
        .defaultClosedDomain,
        .handwrittenCases,
        .uninspectedMacro,
        .rawProcess,
        .detachedTask,
        .globalMutableState,
        .ownedExistential,
        .anyType,
        .mirror,
        .uncheckedArithmetic,
        .directEnvironment,
        .directClock,
        .directRandomness,
        .directFileWrite,
        .unsafeOutsideBoundary,
    ]
    for fixture in LawFixtureCatalog.all where syntactic.contains(fixture.law) {
        let legalPath = fixture.law == .uninspectedMacro
            ? "Sources/SwiftestTesting/Macros.swift"
            : "Sources/Fixture/Fixture.swift"
        let legal = LawScanner.scanSwiftSource(fixture.legal, path: legalPath)
        #expect(!legal.contains(where: { $0.law == fixture.law }))
        let illegal = LawScanner.scanSwiftSource(
            fixture.illegal,
            path: "Sources/Fixture/Fixture.swift"
        )
        #expect(illegal.contains(where: { $0.law == fixture.law }))
    }
}

@Test
func typeStaticMutableStateCannotBypassFileScopeRule() {
    let legal = "enum Globals { static let state = 0 }\n"
    #expect(!LawScanner.scanSwiftSource(legal, path: "Sources/Fixture/Fixture.swift")
        .contains { $0.law == .globalMutableState })
    let illegal = "enum Globals { private static var state = 0 }\n"
    #expect(LawScanner.scanSwiftSource(illegal, path: "Sources/Fixture/Fixture.swift")
        .contains { $0.law == .globalMutableState })
    let classMember = "class Globals { class var state: Int { 0 } }\n"
    #expect(LawScanner.scanSwiftSource(classMember, path: "Sources/Fixture/Fixture.swift")
        .contains { $0.law == .globalMutableState })
}

@Test
func removedSwiftTestingAliasesCannotBeReintroduced() {
    let stateMachine = "@attached(body)\npublic macro StateMachineTest<State: Sendable, Action: Sendable>(model: StateMachineModel<State, Action>, depth: IterationCount) = #externalMacro(module: \"SwiftestMacros\", type: \"StateMachineTestMacro\")"
    #expect(!LawScanner.scanSwiftSource(stateMachine, path: "Sources/SwiftestTesting/Macros.swift")
        .contains { $0.law == .uninspectedMacro })
    let performance = "@attached(peer)\npublic macro PerformanceClaim() = #externalMacro(module: \"SwiftestMacros\", type: \"PerformanceClaimMacro\")"
    #expect(!LawScanner.scanSwiftSource(performance, path: "Sources/SwiftestTesting/Macros.swift")
        .contains { $0.law == .uninspectedMacro })
    let double = "@attached(peer)\npublic macro TestDouble() = #externalMacro(module: \"SwiftestMacros\", type: \"TestDoubleMacro\")"
    #expect(!LawScanner.scanSwiftSource(double, path: "Sources/SwiftestTesting/Macros.swift")
        .contains { $0.law == .uninspectedMacro })
    for name in ["WorldTest", "WorldUITest", "Property", "StateMachineTest", "PerformanceClaim"] {
        let declaration = "public macro " + name
            + "() = #externalMacro(module: \"TestingMacros\", type: \"TestDeclarationMacro\")"
        let violations = LawScanner.scanSwiftSource(
            declaration,
            path: "Sources/SwiftestTesting/Macros.swift"
        )
        #expect(violations.contains { $0.law == .uninspectedMacro && $0.subject == name })
    }
    let oldDouble = "public macro TestDouble() = #externalMacro(module: \"TestingMacros\", type: \"PragmaMacro\")"
    #expect(LawScanner.scanSwiftSource(oldDouble, path: "Sources/SwiftestTesting/Macros.swift")
        .contains { $0.law == .uninspectedMacro && $0.subject == "TestDouble" })
}

@Test
func commentAndOperatorSymbolsInsideStringsAreNeverCode() {
    let source = "let text = \"// try? value! Process() Any Mirror &+ ??\"\n"
    let violations = LawScanner.scanSwiftSource(source, path: "Sources/Fixture/Fixture.swift")
    #expect(violations.isEmpty)
}

@Test
func commentsRemainForbiddenOutsideSwiftYAMLAndLeanStrings() {
    let swift = "let text = #\"// string\"#\nlet value = 1 // comment\n"
    let swiftViolations = LawScanner.scanSwiftSource(swift, path: "Sources/Fixture/Fixture.swift")
    #expect(swiftViolations.filter { $0.law == .forbiddenComment }.count == 1)
    #expect(swiftViolations.contains { $0.law == .forbiddenComment && $0.location.line == 2 })

    let yaml = "text: \"# string\"\nvalue: real # comment\n"
    let yamlComments = OtherSourceLexer.comments(in: yaml, flavor: .hash)
    #expect(yamlComments.map(\.text) == ["# comment"])

    let lean = "def text := \"-- /- string -/\"\n-- comment\n"
    let leanComments = OtherSourceLexer.comments(in: lean, flavor: .lean)
    #expect(leanComments.map(\.text) == ["-- comment"])

    #expect(OtherSourceLexer.validatesJSON(Data("{\"text\":\"// string\"}".utf8)))
    #expect(!OtherSourceLexer.validatesJSON(Data("{\"text\":1 // comment\n}".utf8)))
}

@Test
func licenseAndToolDirectivesAreOnlyAllowedAsExactHeaders() {
    let license = "// SPDX-License-Identifier: MIT\nlet value = 1\n"
    #expect(LawScanner.scanSwiftSource(license, path: "Sources/Fixture/Fixture.swift").isEmpty)

    let misplacedLicense = "let value = 1\n// SPDX-License-Identifier: MIT\n"
    #expect(LawScanner.scanSwiftSource(misplacedLicense, path: "Sources/Fixture/Fixture.swift")
        .contains { $0.law == .forbiddenComment })

    let package = "// swift-tools-version: 6.2\n// SPDX-License-Identifier: MIT\nimport PackageDescription\n"
    #expect(LawScanner.scanSwiftSource(package, path: "Package.swift").isEmpty)

    let embellished = "// swift-tools-version: 6.2 explanatory prose\nimport PackageDescription\n"
    #expect(LawScanner.scanSwiftSource(embellished, path: "Package.swift")
        .contains { $0.law == .forbiddenComment })
}

@Test
func logicalNegationIsNotForceUnwrap() {
    let source = "func check(_ value: Bool) -> Bool { !value }\n"
    let violations = LawScanner.scanSwiftSource(source, path: "Sources/Fixture/Fixture.swift")
    #expect(!violations.contains(where: { $0.law == .forceUnwrap }))
}

@Test
func capabilityBoundDirectoryCreationIsNotAForbiddenDirectWrite() {
    let legal = "try FileSystemBoundary.createDirectory(relativePath: path, capability: capability)\n"
    let illegal = "try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)\n"
    #expect(!LawScanner.scanSwiftSource(legal, path: "Tests/Fixture/Fixture.swift")
        .contains { $0.law == .directFileWrite })
    #expect(LawScanner.scanSwiftSource(illegal, path: "Tests/Fixture/Fixture.swift")
        .contains { $0.law == .directFileWrite })
}

@Test
func scannerRejectsMarkdownUnknownFilesInvalidUTF8AndSymlinks() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-laws-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let markdown = try ArtifactPath.parse("README.md")
    let unknown = try ArtifactPath.parse("unclassified.bin")
    let invalid = try ArtifactPath.parse("Sources/SwiftestModel/invalid.swift")
    let target = try ArtifactPath.parse("target.swift")
    let link = try ArtifactPath.parse("linked.swift")
    try FileSystemBoundary.write(Data("handwritten\n".utf8), relativePath: markdown, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.write(Data("binary\n".utf8), relativePath: unknown, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.write(Data([0xff]), relativePath: invalid, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.write(Data("let value = 1\n".utf8), relativePath: target, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.createSymbolicLink(
        relativePath: link,
        destination: target,
        capability: scratch.issueWriteCapability()
    )
    #expect(try FileSystemBoundary.entryKind(path: scratch.path + "/linked.swift") == .symbolicLink)
    let report = try LawScanner.scan(root: scratch.path)
    #expect(report.violations.contains { $0.law == .handwrittenDocumentation && $0.location.file == "README.md" })
    #expect(report.violations.contains { $0.law == .unclassifiedSource && $0.location.file == "unclassified.bin" })
    #expect(report.violations.contains {
        $0.law == .unreadableSource && $0.location.file == "Sources/SwiftestModel/invalid.swift"
    })
    #expect(report.violations.contains { $0.law == .unreadableSource && $0.location.file == "linked.swift" })
    #expect(report.violations.contains {
        $0.law == .unclassifiedTarget
            && $0.location.file == "Sources/SwiftestMacros"
            && $0.subject == "missing-target"
    })
}

@Test
func scannerRejectsOutputArtifactsEvenWithRecognizedExtensions() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-laws-artifacts-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let report = try ArtifactPath.parse("report.json")
    let targetResource = try ArtifactPath.parse("Sources/SwiftestModel/Resources/result.json")
    let workflowOutput = try ArtifactPath.parse(".github/workflows/result.xml")
    try FileSystemBoundary.write(Data("{}".utf8), relativePath: report, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.write(
        Data("{}".utf8),
        relativePath: targetResource,
        capability: scratch.issueWriteCapability()
    )
    try FileSystemBoundary.write(
        Data("<testsuite/>".utf8),
        relativePath: workflowOutput,
        capability: scratch.issueWriteCapability()
    )
    let result = try LawScanner.scan(root: scratch.path)
    #expect(result.violations.contains { $0.law == .unclassifiedSource && $0.location.file == "report.json" })
    #expect(result.violations.contains {
        $0.law == .unclassifiedSource && $0.location.file == "Sources/SwiftestModel/Resources/result.json"
    })
    #expect(result.violations.contains {
        $0.law == .unclassifiedSource && $0.location.file == ".github/workflows/result.xml"
    })
}

@Test
func packageManifestMustMatchTheTypedModuleGraph() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .path
    let data = try FileSystemBoundary.read(path: root + "/Package.swift")
    let source = String(decoding: data, as: UTF8.self)
    #expect(PackageManifestGraph.violations(in: source).isEmpty)
    let original = ".target(name: \"SwiftestFaults\", dependencies: [\"SwiftestModel\"]"
    #expect(source.contains(original))
    let changed = source.replacingOccurrences(
        of: original,
        with: ".target(name: \"SwiftestFaults\", dependencies: [\"UnapprovedExternal\"]"
    )
    let violations = PackageManifestGraph.violations(in: changed)
    #expect(violations.contains(where: { $0.law == .forbiddenDependency }))
    #expect(violations.contains(where: { $0.law == .reverseDependency }))
    let packageDependency = source.replacingOccurrences(
        of: "targets: [",
        with: "dependencies: [.package(url: \"https://example.invalid/package\", from: \"1.0.0\")], targets: ["
    )
    #expect(PackageManifestGraph.violations(in: packageDependency).contains(where: { $0.law == .forbiddenDependency }))
    let missingPlugin = source.replacingOccurrences(
        of: "plugins: [\"SwiftestLawsPlugin\"]",
        with: "plugins: []"
    )
    #expect(PackageManifestGraph.violations(in: missingPlugin).contains(where: {
        $0.law == .unclassifiedTarget && $0.subject.contains("missing-plugin")
    }))
    let cyclicPlugin = source.replacingOccurrences(
        of: ".target(name: \"SwiftestModel\", swiftSettings: strict)",
        with: ".target(name: \"SwiftestModel\", swiftSettings: strict, plugins: [\"SwiftestLawsPlugin\"])"
    )
    #expect(PackageManifestGraph.violations(in: cyclicPlugin).contains(where: {
        $0.law == .reverseDependency && $0.subject == "SwiftestModel:plugin:SwiftestLawsPlugin"
    }))
    let weakenedLanguage = source.replacingOccurrences(
        of: "swiftLanguageModes: [.v6]",
        with: "swiftLanguageModes: [.v5]"
    )
    #expect(PackageManifestGraph.violations(in: weakenedLanguage).contains(where: {
        $0.law == .unclassifiedTarget && $0.subject == "swift-language-mode"
    }))
    let weakenedWarnings = source.replacingOccurrences(
        of: "\"-warnings-as-errors\",",
        with: ""
    )
    #expect(PackageManifestGraph.violations(in: weakenedWarnings).contains(where: {
        $0.law == .unclassifiedTarget && $0.subject == "settings:strict"
    }))
    let weakenedTarget = source.replacingOccurrences(
        of: ".target(name: \"SwiftestFaults\", dependencies: [\"SwiftestModel\"], swiftSettings: strict",
        with: ".target(name: \"SwiftestFaults\", dependencies: [\"SwiftestModel\"], swiftSettings: []"
    )
    #expect(PackageManifestGraph.violations(in: weakenedTarget).contains(where: {
        $0.law == .unclassifiedTarget && $0.subject == "settings:SwiftestFaults"
    }))
    let unknownTargetArgument = source.replacingOccurrences(
        of: ".target(name: \"SwiftestFaults\", dependencies: [\"SwiftestModel\"], swiftSettings: strict",
        with: ".target(name: \"SwiftestFaults\", dependencies: [\"SwiftestModel\"], swiftSettings: strict, cSettings: []"
    )
    #expect(PackageManifestGraph.violations(in: unknownTargetArgument).contains(where: {
        $0.law == .unclassifiedTarget && $0.subject == "dynamic-target"
    }))
    let unknownPackageArgument = source.replacingOccurrences(
        of: "name: \"Swiftest\",",
        with: "name: \"Swiftest\", unknownFlag: true,"
    )
    #expect(PackageManifestGraph.violations(in: unknownPackageArgument).contains(where: {
        $0.law == .unclassifiedTarget && $0.subject == "package-arguments"
    }))
    let mutatedAfterConstruction = source + "\npackage.targets = []\n"
    #expect(PackageManifestGraph.violations(in: mutatedAfterConstruction).contains(where: {
        $0.law == .unclassifiedTarget && $0.subject == "manifest-top-level"
    }))
    let shadowedPackage = source.replacingOccurrences(
        of: "let package = Package(",
        with: "let shadow = Package("
    )
    #expect(PackageManifestGraph.violations(in: shadowedPackage).contains(where: {
        $0.law == .unclassifiedTarget && $0.subject == "manifest-top-level"
    }))
    let missingPlatform = source.replacingOccurrences(
        of: ".watchOS(.v10),",
        with: ""
    )
    #expect(PackageManifestGraph.violations(in: missingPlatform).contains(where: {
        $0.law == .unclassifiedTarget && $0.subject == "platforms"
    }))
    let missingExecutable = source.replacingOccurrences(
        of: ".executable(name: \"swiftest\", targets: [\"SwiftestCLI\"]),",
        with: ""
    )
    #expect(PackageManifestGraph.violations(in: missingExecutable).contains(where: {
        $0.law == .unclassifiedTarget && $0.subject == "products"
    }))
}

@Test
func lawBuildPluginExemptionsAreExactlyItsDependencyClosure() {
    let exempt = Set(SwiftestModuleGraph.declarations
        .filter { !SwiftestModuleGraph.requiresLawPlugin(for: $0) }
        .map(\.name))
    #expect(exempt == Set([
        "SwiftestCodec",
        "SwiftestLaws",
        "SwiftestLawTool",
        "SwiftestLawsPlugin",
        "SwiftestModel",
        "SwiftestPlatform",
    ]))
}

@Test
func systemCryptoKitImportDoesNotAuthorizeAnUnknownDependency() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-laws-imports-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let source = try ArtifactPath.parse("Tests/SwiftestModelTests/Imports.swift")
    try FileSystemBoundary.write(
        Data("import CryptoKit\nimport UnapprovedExternal\n".utf8),
        relativePath: source,
        capability: scratch.issueWriteCapability()
    )
    let report = try LawScanner.scan(root: scratch.path)
    #expect(!report.violations.contains { $0.law == .reverseDependency && $0.subject == "CryptoKit" })
    #expect(report.violations.contains {
        $0.law == .reverseDependency && $0.subject == "UnapprovedExternal"
    })
}

@Test
func macroSourcesAndExpansionFixtureReceiveDirectSwiftSyntaxInspection() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .path
    let directory = root + "/Sources/SwiftestMacros"
    let entries = try FileSystemBoundary.list(path: directory)
    #expect(!entries.isEmpty)
    let paths = entries.map { "Sources/SwiftestMacros/" + $0 }
        + ["Tests/SwiftestTestingTests/TestingTests.swift"]
    for relative in paths {
        #expect(relative.hasSuffix(".swift"))
        #expect(try FileSystemBoundary.entryKind(path: root + "/" + relative) == .file)
        let data = try FileSystemBoundary.read(path: root + "/" + relative)
        guard let source = String(data: data, encoding: .utf8) else {
            Issue.record("invalid UTF-8 in \(relative)")
            continue
        }
        #expect(LawScanner.scanSwiftSource(source, path: relative).isEmpty)
    }
}

@Test
func macroTargetSymlinkCannotMasqueradeAsAnInspectedDirectory() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-laws-macro-link-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let real = try ArtifactPath.parse("Sources/SwiftestModel")
    let macro = try ArtifactPath.parse("Sources/SwiftestMacros")
    try FileSystemBoundary.createDirectory(relativePath: real, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.createSymbolicLink(
        relativePath: macro,
        destination: real,
        capability: scratch.issueWriteCapability()
    )
    let report = try LawScanner.scan(root: scratch.path)
    #expect(report.violations.contains {
        $0.law == .unreadableSource && $0.location.file == "Sources/SwiftestMacros"
    })
    #expect(report.violations.contains {
        $0.law == .unclassifiedTarget
            && $0.location.file == "Sources/SwiftestMacros"
            && $0.subject == "not-directory"
    })
}

@Test
func swiftSyntaxVersionComesFromTheHostModuleInterface() throws {
    let interface = "// swift-module-flags: -module-name SwiftSyntax -user-module-version 6.4.0.34.1\n"
    #expect(try ToolchainAudit.parseSwiftSyntaxModuleVersion(interface) == ToolchainAudit.swiftSyntaxModuleVersion)
    do {
        let version = try ToolchainAudit.parseSwiftSyntaxModuleVersion("// swift-module-flags: -module-name Other\n")
        Issue.record("unrelated host module accepted")
        #expect(version.isEmpty)
    } catch let error {
        #expect(error == .swiftSyntaxMetadata("missing-module-version"))
    }
}

@Test
func pinnedToolchainVersionsRequireExactVersionTokens() {
    let cases: [(component: String, expected: String, output: String, status: Observation)] = [
        ("Swift", "6.4", "Apple Swift version 6.4 (swiftlang-6.4.0)\nTarget: arm64-apple-macosx", .matched),
        ("Swift", "6.4", "swift-driver version: 1.168.6 Apple Swift version 6.4 (swiftlang-6.4.0)", .matched),
        ("Swift", "6.4", "Apple Swift version 6.4.1 (swiftlang-6.4.1)", .mismatched),
        ("Xcode", "27.0", "Xcode 27.0\nBuild version 27A123", .matched),
        ("Xcode", "27.0", "Xcode 27.0.1\nBuild version 27A124", .mismatched),
        ("Lean", "4.34.1", "Lean (version 4.34.1, x86_64-apple-darwin)", .matched),
        ("Lean", "4.34.1", "Lean (version 4.34.10, x86_64-apple-darwin)", .mismatched),
        ("Swift", "6.4", "Other Swift version 6.4", .mismatched),
    ]
    for entry in cases {
        #expect(ToolchainAudit.observation(
            component: entry.component,
            expected: entry.expected,
            actual: entry.output
        ).status == entry.status)
    }
}
