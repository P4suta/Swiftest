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
    for fixture in LawFixtureCatalog.all {
        guard case .swiftSource(let path) = fixture.verification else {
            continue
        }
        let legal = LawScanner.scanSwiftSource(fixture.legal, path: path.rawValue)
        #expect(!legal.contains(where: { $0.law == fixture.law }))
        let illegal = LawScanner.scanSwiftSource(fixture.illegal, path: path.rawValue)
        #expect(illegal.contains(where: { $0.law == fixture.law }))
    }
}

@Test
func swiftPackageFaultVerdictRequiresObserverReceipt() {
    let path = "Sources/SwiftestEngine/SwiftPackageBoundaryFaultCampaign.swift"
    guard let fixture = LawFixtureCatalog.all.first(where: { $0.law == .faultObservationProvenance }) else {
        Issue.record("fault observation provenance fixture is missing")
        return
    }
    #expect(!LawScanner.scanSwiftSource(fixture.legal, path: path)
        .contains { $0.law == .faultObservationProvenance })
    let forged = LawScanner.scanSwiftSource(fixture.illegal, path: path)
        .filter { $0.law == .faultObservationProvenance }
    #expect(Set(forged.map(\.subject)) == [
        "denial-receipt-issuance", "denial-receipt-consumption", "direct-fault-verdict",
    ])
    let opaque = fixture.legal + "let message = \".handled(.failedClosed)\"\n"
    #expect(!LawScanner.scanSwiftSource(opaque, path: path)
        .contains { $0.law == .faultObservationProvenance })
    let removedObserver = fixture.legal.replacingOccurrences(
        of: "SwiftPackageTargetObserver.denialReceipt(.evidence)",
        with: "forgedReceipt"
    )
    #expect(LawScanner.scanSwiftSource(removedObserver, path: path).contains {
        $0.law == .faultObservationProvenance && $0.subject == "denial-receipt-issuance"
    })
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
func generatedMacroOutputIsCheckedByTheCompilerResponseGate() {
    let legal = "static let cases: [Self] = [.one]\nvar code: String { switch self { case .one: return \"one\" } }\n"
    #expect(MacroExpansionLawGate.inspect(legal, role: .member) == .accepted)
    let diagnosticText = "let message = \"<#value#> // Process()\"\n"
    #expect(MacroExpansionLawGate.inspect(diagnosticText, role: .body) == .accepted)

    let injectedOutputs: [(String, LawCode)] = [
        ("let generated = Process()\n", .rawProcess),
        ("let generated = try? operation()\n", .prohibitedTry),
        ("let generated = 1 // hidden output\n", .forbiddenComment),
        ("let generated = #externalMacro(module: \"Unknown\", type: \"Unknown\")\n", .uninspectedMacro),
    ]
    for (source, expectedLaw) in injectedOutputs {
        guard case .rejected(let violations) = MacroExpansionLawGate.inspect(source, role: .body) else {
            Issue.record("generated macro output was accepted")
            continue
        }
        #expect(violations.contains { $0.law == expectedLaw })
    }
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
    let yamlComments = OtherSourceLexer.scan(in: yaml, flavor: .hash).comments
    #expect(yamlComments.map(\.text) == ["# comment"])

    let lean = "def text := \"-- /- string -/\"\n-- comment\n"
    let leanComments = OtherSourceLexer.scan(in: lean, flavor: .lean).comments
    #expect(leanComments.map(\.text) == ["-- comment"])

    #expect(OtherSourceLexer.validatesJSON(Data("{\"text\":\"// string\"}".utf8)))
    #expect(!OtherSourceLexer.validatesJSON(Data("{\"text\":1 // comment\n}".utf8)))
}

@Test
func workflowVersionAnnotationsRequirePinnedActions() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-action-versions-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let workflow = try ArtifactPath.parse(".github/workflows/quality.yml")
    let hash = "fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09"
    let lines = [
        "  - uses: actions/checkout@\(hash) # v5.1.0",
        "    uses: actions/checkout@\(hash) # v5.1.0",
        "  - uses: actions/checkout@v5 # v5.1.0",
        "  - uses: actions/checkout@\(hash.dropLast()) # v5.1.0",
        "  - uses: actions/checkout@\(hash) # v5.1.0 annotation",
        "  - uses: actions/checkout@\(hash) # v5",
        "  - run: actions/checkout@\(hash) # v5.1.0",
        "# v5.1.0",
    ]
    try FileSystemBoundary.write(
        Data((lines.joined(separator: "\n") + "\n").utf8),
        relativePath: workflow,
        capability: scratch.issueWriteCapability()
    )
    let script = try ArtifactPath.parse("Scripts/quality")
    try FileSystemBoundary.write(
        Data((lines[0] + "\n").utf8),
        relativePath: script,
        capability: scratch.issueWriteCapability()
    )
    let report = try LawScanner.scan(root: scratch.path)
    let comments = report.violations.filter { $0.law == .forbiddenComment }
    #expect(comments.filter { $0.location.file == ".github/workflows/quality.yml" }
        .map(\.location.line).sorted() == [3, 4, 5, 6, 7, 8])
    #expect(comments.contains { $0.location.file == "Scripts/quality" })
}

@Test
func lawScannerRejectsLeanRawStringBeforeHiddenProofHole() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-lean-raw-law-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let raw = try ArtifactPath.parse("SwiftestProofs/Raw.lean")
    let ordinary = try ArtifactPath.parse("SwiftestProofs/Ordinary.lean")
    let hiddenAxiom = #"""
    def marker := r"\"
    axiom hidden : False
    def trailing := "\""
    """# + "\n"
    try FileSystemBoundary.write(Data(hiddenAxiom.utf8), relativePath: raw, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.write(
        Data("def marker := \"r\\\"safe\\\"\"\n".utf8),
        relativePath: ordinary,
        capability: scratch.issueWriteCapability()
    )
    let report = try LawScanner.scan(root: scratch.path)
    #expect(report.violations.contains {
        $0.law == .unreadableSource && $0.location.file == raw.rawValue && $0.subject == "lean-raw-string"
    })
    #expect(!report.violations.contains { $0.location.file == ordinary.rawValue })
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
    let workflowLint = try ArtifactPath.parse(".github/actionlint.yaml")
    let workflowLintOutput = try ArtifactPath.parse(".github/actionlint-output.yaml")
    let distributionOutput = try ArtifactPath.parse("dist/Generated.swift")
    let signingOutput = try ArtifactPath.parse(".local-signing/Generated.swift")
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
    for path in [workflowLint, workflowLintOutput] {
        try FileSystemBoundary.write(
            Data("self-hosted-runner:\n  labels:\n    - xcode-27\n".utf8),
            relativePath: path,
            capability: scratch.issueWriteCapability()
        )
    }
    try FileSystemBoundary.write(
        Data("// generated\n".utf8),
        relativePath: distributionOutput,
        capability: scratch.issueWriteCapability()
    )
    try FileSystemBoundary.write(
        Data("// generated\n".utf8),
        relativePath: signingOutput,
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
    #expect(!result.violations.contains { $0.location.file == ".github/actionlint.yaml" })
    #expect(result.violations.contains {
        $0.law == .unclassifiedSource && $0.location.file == ".github/actionlint-output.yaml"
    })
    #expect(!result.violations.contains {
        $0.location.file == "dist/Generated.swift" || $0.location.file == ".local-signing/Generated.swift"
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
func systemImportsAreGrantedPerModuleAndDarwinOnlyToABIAdapter() throws {
    #expect(!SwiftestModuleGraph.permitsSystemImport(
        "Darwin",
        declaration: ModuleDeclaration(
            name: "SwiftestEngine",
            dependencies: [],
            role: .production,
            systemImports: ["Darwin"]
        ),
        relativePath: "Sources/SwiftestPlatform/ABIAdapter.swift"
    ))
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-laws-system-imports-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let model = try ArtifactPath.parse("Sources/SwiftestModel/Unsafe.swift")
    let platform = try ArtifactPath.parse("Sources/SwiftestPlatform/Unsafe.swift")
    let adapter = try ArtifactPath.parse("Sources/SwiftestPlatform/ABIAdapter.swift")
    try FileSystemBoundary.write(
        Data("import Foundation\nimport CryptoKit\nimport func Darwin.open\n".utf8),
        relativePath: model,
        capability: scratch.issueWriteCapability()
    )
    try FileSystemBoundary.write(
        Data("import Darwin\n".utf8),
        relativePath: platform,
        capability: scratch.issueWriteCapability()
    )
    try FileSystemBoundary.write(
        Data("import Darwin\n".utf8),
        relativePath: adapter,
        capability: scratch.issueWriteCapability()
    )
    let report = try LawScanner.scan(root: scratch.path)
    #expect(report.violations.contains {
        $0.law == .reverseDependency && $0.location.file == "Sources/SwiftestModel/Unsafe.swift"
            && $0.subject == "CryptoKit"
    })
    #expect(report.violations.contains {
        $0.law == .reverseDependency && $0.location.file == "Sources/SwiftestModel/Unsafe.swift"
            && $0.subject == "Darwin"
    })
    #expect(report.violations.contains {
        $0.law == .reverseDependency && $0.location.file == "Sources/SwiftestPlatform/Unsafe.swift"
            && $0.subject == "Darwin"
    })
    #expect(!report.violations.contains {
        $0.law == .reverseDependency && $0.location.file == "Sources/SwiftestPlatform/ABIAdapter.swift"
            && $0.subject == "Darwin"
    })
    #expect(!report.violations.contains {
        $0.law == .reverseDependency && $0.location.file == "Sources/SwiftestModel/Unsafe.swift"
            && $0.subject == "Foundation"
    })
}

@Test
func pluginInputsMustExactlyMatchTheScannerInventory() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-laws-plugin-inputs-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let file = "Sources/SwiftestModel/Value.swift"
    try FileSystemBoundary.write(
        Data("public struct Value {}\n".utf8),
        relativePath: ArtifactPath.parse(file),
        capability: scratch.issueWriteCapability()
    )
    let missing = try LawScanner.scan(root: scratch.path, declaredInputs: [])
    #expect(missing.violations.contains {
        $0.law == .unclassifiedSource && $0.location.file == file
            && $0.subject == "plugin-input-closure"
    })
    let matching = try LawScanner.scan(root: scratch.path, declaredInputs: [file])
    #expect(!matching.violations.contains { $0.subject == "plugin-input-closure" })
    let duplicate = try LawScanner.scan(root: scratch.path, declaredInputs: [file, file])
    #expect(duplicate.violations.contains { $0.subject == "duplicate-plugin-input" })
    let extra = try LawScanner.scan(root: scratch.path, declaredInputs: [file, "ghost.swift"])
    #expect(extra.violations.contains {
        $0.location.file == "ghost.swift" && $0.subject == "plugin-input-closure"
    })
}

@Test
func directLibcFilesystemAndProcessOperationsRequireABIAdapter() {
    let illegal = [
        "Darwin.open(\"/tmp/value\", O_WRONLY)",
        "open(\"/tmp/value\", O_WRONLY)",
        "fopen(\"/tmp/value\", \"w\")",
        "unlink(\"/tmp/value\")",
        "rename(\"/tmp/value\", \"/tmp/next\")",
        "write(1, bytes, count)",
        "Foundation.write(1, bytes, count)",
        "remove(\"/tmp/value\")",
        "Foundation.remove(\"/tmp/value\")",
    ]
    for source in illegal {
        #expect(LawScanner.scanSwiftSource(source, path: "Sources/SwiftestEngine/Unsafe.swift")
            .contains { $0.law == .directFileWrite })
    }
    let process = ["system(\"touch /tmp/value\")", "posix_spawn(&pid, path, nil, nil, argv, env)"]
    for source in process {
        #expect(LawScanner.scanSwiftSource(source, path: "Sources/SwiftestEngine/Unsafe.swift")
            .contains { $0.law == .rawProcess })
    }
    let foreignSymbol = "@_silgen_name(\"unlink\") func erase(_ path: UnsafePointer<CChar>) -> Int32"
    #expect(LawScanner.scanSwiftSource(foreignSymbol, path: "Sources/SwiftestEngine/Unsafe.swift")
        .contains { $0.law == .unsafeOutsideBoundary && $0.subject == "_silgen_name" })
    for source in [
        "FileSystemBoundary.write(data, relativePath: path, capability: capability)",
        "FileSystemBoundary.remove(relativePath: path, capability: capability)",
    ] {
        #expect(!LawScanner.scanSwiftSource(source, path: "Sources/SwiftestEngine/Safe.swift")
            .contains { $0.law == .directFileWrite })
    }
    #expect(!LawScanner.scanSwiftSource(
        "Darwin.open(\"/tmp/value\", O_RDONLY)",
        path: "Sources/SwiftestPlatform/ABIAdapter.swift"
    ).contains { $0.law == .directFileWrite })
    #expect(!LawScanner.scanSwiftSource(
        "switch error { case .pathEscapesRoot, .createDirectory: break; default: break }",
        path: "Tests/SwiftestLawsTests/ResourceBoundaryTests.swift"
    ).contains { $0.law == .directFileWrite })
    #expect(!LawScanner.scanSwiftSource(
        "FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)",
        path: "Plugins/SwiftestLawsPlugin/PluginInputInventory.swift"
    ).contains { $0.law == .directFileWrite })
    #expect(LawScanner.scanSwiftSource(
        "FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)",
        path: "Plugins/SwiftestLawsPlugin/PluginInputInventory.swift"
    ).contains { $0.law == .directFileWrite })
    #expect(LawScanner.scanSwiftSource(
        "FileManager.default.removeItem(at: stamp)",
        path: "Plugins/SwiftestLawsPlugin/SwiftestLawsPlugin.swift"
    ).contains { $0.law == .directFileWrite })
}

@Test
func vnodeEventRegistrationHasOneClearingABIConstructor() throws {
    guard let fixture = LawFixtureCatalog.all.first(where: { $0.law == .vnodeEventProtocol }) else {
        Issue.record("missing vnode event Law fixture")
        return
    }
    let abiPath = "Sources/SwiftestPlatform/ABIAdapter.swift"
    #expect(!LawScanner.scanSwiftSource(fixture.legal, path: abiPath)
        .contains { $0.law == .vnodeEventProtocol })
    #expect(LawScanner.scanSwiftSource(fixture.illegal, path: abiPath)
        .contains { $0.law == .vnodeEventProtocol && $0.subject == "registration-shape" })
    #expect(LawScanner.scanSwiftSource(fixture.legal, path: "Sources/Fixture/Fixture.swift")
        .contains { $0.law == .vnodeEventProtocol && $0.subject == "raw-vnode-filter" })
    let dynamicRaw = "let event = Darwin.kevent64_s(filter: filterValue, flags: flags)\n"
    #expect(LawScanner.scanSwiftSource(dynamicRaw, path: "Sources/Fixture/Fixture.swift")
        .contains { $0.law == .vnodeEventProtocol && $0.subject == "raw-event-queue" })
    let moved = fixture.legal.replacingOccurrences(
        of: "makeVnodeRegistration", with: "registerSomewhereElse"
    )
    #expect(LawScanner.scanSwiftSource(moved, path: abiPath)
        .contains { $0.law == .vnodeEventProtocol })
    let exposed = fixture.legal.replacingOccurrences(
        of: "private static func", with: "func"
    )
    #expect(LawScanner.scanSwiftSource(exposed, path: abiPath)
        .contains { $0.law == .vnodeEventProtocol })
    let doubled = fixture.legal + fixture.legal
    #expect(LawScanner.scanSwiftSource(doubled, path: abiPath)
        .contains { $0.law == .vnodeEventProtocol })
    let disguised = fixture.legal.replacingOccurrences(
        of: "Int16(EVFILT_VNODE)", with: "filterValue"
    )
    #expect(LawScanner.scanSwiftSource(disguised, path: abiPath)
        .contains { $0.law == .vnodeEventProtocol })
    let literal = "let diagnostic = \"EVFILT_VNODE EV_CLEAR kevent64_s\"\n"
    #expect(!LawScanner.scanSwiftSource(literal, path: "Sources/Fixture/Fixture.swift")
        .contains { $0.law == .vnodeEventProtocol })

    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .path
    let source = try FileSystemBoundary.read(path: root + "/" + abiPath)
    guard let text = String(data: source, encoding: .utf8) else {
        Issue.record("ABI adapter has invalid UTF-8")
        return
    }
    #expect(!LawScanner.scanSwiftSource(text, path: abiPath)
        .contains { $0.law == .vnodeEventProtocol })
}

@Test
func vnodeRegistrationSourceCannotDisappearFromLawInventory() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-vnode-law-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let missing = try LawScanner.scan(root: scratch.path)
    #expect(missing.violations.contains {
        $0.law == .vnodeEventProtocol && $0.subject == "registration-source-missing"
    })
}

@Test
func vnodeRegistrationLawBindsFlagsConstructorAndActualKeventCall() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .path
    let adapterPath = "Sources/SwiftestPlatform/ABIAdapter.swift"
    let sourceData = try FileSystemBoundary.read(path: root + "/" + adapterPath)
    guard let source = String(data: sourceData, encoding: .utf8) else {
        Issue.record("ABI adapter has invalid UTF-8")
        return
    }
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-vnode-pipeline-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let relative = try ArtifactPath.parse(adapterPath)
    try FileSystemBoundary.write(
        sourceData,
        relativePath: relative,
        capability: scratch.issueWriteCapability()
    )
    let legal = try LawScanner.scan(root: scratch.path)
    #expect(!legal.violations.contains { $0.law == .vnodeEventProtocol })

    let construction = "            var event = ABIAdapter.makeVnodeRegistration(\n"
        + "                descriptor: watchedDescriptor,\n"
        + "                mutationFlags: mutationFlags\n"
        + "            )"
    let mutations: [(String, String)] = [
        ("NOTE_REVOKE | NOTE_ATTRIB", "NOTE_REVOKE"),
        (construction, "            var event = Darwin.kevent64_s()"),
        (construction, construction + "\n            event.flags = UInt16(EV_ADD | EV_ENABLE)"),
        ("Darwin.kevent64(descriptor, change, 1, nil, 0, 0, nil)",
            "Darwin.kevent64(descriptor, nil, 0, nil, 0, 0, nil)"),
        ("let count = Darwin.kevent64(",
            "let alias = Darwin.kevent64\n            let count = Darwin.kevent64("),
    ]
    for (original, replacement) in mutations {
        #expect(source.contains(original))
        let mutant = source.replacingOccurrences(of: original, with: replacement)
        #expect(mutant != source)
        try FileSystemBoundary.write(
            Data(mutant.utf8),
            relativePath: relative,
            capability: scratch.issueWriteCapability()
        )
        let report = try LawScanner.scan(root: scratch.path)
        #expect(report.violations.contains {
            $0.law == .vnodeEventProtocol && $0.subject == "registration-path"
        })
    }
}

@Test
func claimDefinitionSerializationRequiresBoundIDAndName() {
    let model = "struct IndependentReview { let status: ReviewStatus }\n"
        + "struct Claim<Polarity> { let id: ClaimID; let name: String }\n"
        + "struct EvidenceCatalog { let preservationClaims: DeclaredClaims<Preservation> }\n"
    let fixture = LawFixtureCatalog.claimDefinitionEncoding
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: model,
        reportSource: fixture.legal
    ).isEmpty)
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: model,
        reportSource: fixture.illegal
    ).contains { $0.subject == "preservationClaims-missing:name" })
    let constantName = fixture.legal.replacingOccurrences(
        of: "\"name\": .string(claim.name)",
        with: "\"name\": .string(\"fixed\")"
    )
    #expect(constantName != fixture.legal)
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: model,
        reportSource: constantName
    ).contains { $0.subject == "preservationClaims-binding:name" })
    let inertName = fixture.legal.replacingOccurrences(
        of: ".string(claim.name)",
        with: ".string(claim.name.isEmpty ? \"fixed\" : \"fixed\")"
    )
    #expect(inertName != fixture.legal)
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: model,
        reportSource: inertName
    ).contains { $0.subject == "preservationClaims-transformation:name" })
    let constantID = fixture.legal.replacingOccurrences(
        of: "\"id\": .string(claim.id.rawValue)",
        with: "\"id\": .string(\"fixed\")"
    )
    #expect(constantID != fixture.legal)
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: model,
        reportSource: constantID
    ).contains { $0.subject == "preservationClaims-binding:id" })
    let detectionModel = model.replacingOccurrences(
        of: "preservationClaims: DeclaredClaims<Preservation>",
        with: "detectionClaims: DeclaredClaims<Detection>"
    )
    let detectionLegal = fixture.legal.replacingOccurrences(
        of: "preservationClaims",
        with: "detectionClaims"
    )
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: detectionModel,
        reportSource: detectionLegal
    ).isEmpty)
    let detectionIllegal = fixture.illegal.replacingOccurrences(
        of: "preservationClaims",
        with: "detectionClaims"
    )
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: detectionModel,
        reportSource: detectionIllegal
    ).contains { $0.subject == "detectionClaims-missing:name" })
}

@Test
func catalogSerializationBindsEveryStoredPropertyToItsOwnCanonicalField() throws {
    guard let fixture = LawFixtureCatalog.all.first(where: { $0.law == .catalogSerialization }) else {
        Issue.record("missing catalog serialization Law fixture")
        return
    }
    let reviewModel = "struct IndependentReview { let status: ReviewStatus; let evidence: Digest? }\n"
    let model = reviewModel + "struct EvidenceCatalog { let run: RunID }\n"
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: model,
        reportSource: fixture.legal
    ).isEmpty)
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: model,
        reportSource: fixture.illegal
    ).contains { $0.law == .catalogSerialization && $0.subject == "missing:run" })
    let expandedModel = reviewModel + "struct EvidenceCatalog { let run: RunID; let scope: ScopeKind }\n"
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: expandedModel,
        reportSource: fixture.legal
    ).contains { $0.subject == "missing:scope" })
    let extra = fixture.legal.replacingOccurrences(
        of: "\"run\": .string(catalog.run.rawValue)",
        with: "\"run\": .string(catalog.run.rawValue), \"scope\": .string(catalog.run.rawValue)"
    )
    let extraViolations = LawScanner.catalogSerializationViolations(modelSource: model, reportSource: extra)
    #expect(extraViolations.contains { $0.subject == "extra:scope" })
    #expect(extraViolations.contains { $0.subject == "binding:scope" })
    let duplicate = fixture.legal.replacingOccurrences(
        of: "\"run\": .string(catalog.run.rawValue)",
        with: "\"run\": .string(catalog.run.rawValue), \"run\": .string(catalog.run.rawValue)"
    )
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: model,
        reportSource: duplicate
    ).contains { $0.subject == "duplicate:run" })
    let swapped = "enum ReportCodec { private static func catalogValue(_ catalog: EvidenceCatalog) -> JSONValue { return .object([\"run\": .string(catalog.scope.rawValue), \"scope\": .string(catalog.run.rawValue)]) } }\n"
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: expandedModel,
        reportSource: swapped
    ).filter { $0.subject.hasPrefix("binding:") }.count == 2)
    let dynamic = "enum ReportCodec { private static func catalogValue(_ catalog: EvidenceCatalog) -> JSONValue { let key = \"run\"; return .object([key: .string(catalog.run.rawValue)]) } }\n"
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: model,
        reportSource: dynamic
    ).contains { $0.subject == "serializer-shape" })
    let inertReference = fixture.legal.replacingOccurrences(
        of: ".string(catalog.run.rawValue)",
        with: ".string(catalog.run.rawValue.isEmpty ? \"fixed\" : \"fixed\")"
    )
    #expect(inertReference != fixture.legal)
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: model,
        reportSource: inertReference
    ).contains { $0.subject == "transformation:run" })

    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .path
    let modelData = try FileSystemBoundary.read(path: root + "/Sources/SwiftestModel/Evidence.swift")
    let claimsData = try FileSystemBoundary.read(path: root + "/Sources/SwiftestModel/Claims.swift")
    let worldData = try FileSystemBoundary.read(path: root + "/Sources/SwiftestModel/World.swift")
    let reportData = try FileSystemBoundary.read(path: root + "/Sources/SwiftestReport/AssuredReport.swift")
    guard let evidenceSource = String(data: modelData, encoding: .utf8),
        let claimsSource = String(data: claimsData, encoding: .utf8),
        let worldSource = String(data: worldData, encoding: .utf8),
        let reportSource = String(data: reportData, encoding: .utf8) else {
        Issue.record("catalog sources have invalid UTF-8")
        return
    }
    let modelSource = evidenceSource + "\n" + worldSource
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: modelSource + "\n" + claimsSource,
        reportSource: reportSource
    ).isEmpty)
    let missingWorldAxis = reportSource.replacingOccurrences(
        of: "                \"serviceFault\": .string(world.serviceFault.rawValue),\n",
        with: ""
    )
    let worldFixture = LawFixture(law: .catalogSerialization, legal: reportSource, illegal: missingWorldAxis)
    #expect(worldFixture.illegal != worldFixture.legal)
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: modelSource + "\n" + claimsSource,
        reportSource: worldFixture.illegal
    ).contains { $0.subject == "world-definition" })
    let unboundWorldAxis = reportSource.replacingOccurrences(
        of: "\"serviceFault\": .string(world.serviceFault.rawValue)",
        with: "\"serviceFault\": .string(\"none\")"
    )
    #expect(unboundWorldAxis != reportSource)
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: modelSource + "\n" + claimsSource,
        reportSource: unboundWorldAxis
    ).contains { $0.subject == "world-definition" })
    let legacyIDOnlyWorld = reportSource.replacingOccurrences(
        of: ".array(catalog.worlds.definitions.map(worldValue))",
        with: ".array(catalog.worlds.map { .string($0.rawValue) })"
    )
    #expect(legacyIDOnlyWorld != reportSource)
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: modelSource + "\n" + claimsSource,
        reportSource: legacyIDOnlyWorld
    ).contains { $0.subject == "transformation:worlds" })
    let unboundSchedule = reportSource.replacingOccurrences(
        of: ".array(world.schedule.decisions.map { .number(String($0)) })",
        with: ".array(world.schedule.decisions.map { .number(\"0\") })"
    )
    #expect(unboundSchedule != reportSource)
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: modelSource + "\n" + claimsSource,
        reportSource: unboundSchedule
    ).contains { $0.subject == "world-definition" })
    let extendedWorld = worldSource.replacingOccurrences(
        of: "public struct WorldDefinition: Hashable, Sendable {\n",
        with: "public struct WorldDefinition: Hashable, Sendable {\n    public let keyboard: String\n"
    )
    #expect(extendedWorld != worldSource)
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: evidenceSource + "\n" + claimsSource + "\n" + extendedWorld,
        reportSource: reportSource
    ).contains { $0.subject == "world-definition" })
    let missingReviewEvidence = reportSource.replacingOccurrences(
        of: "                \"evidence\": digestValue(catalog.review.evidence),\n",
        with: ""
    )
    #expect(missingReviewEvidence != reportSource)
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: modelSource + "\n" + claimsSource,
        reportSource: missingReviewEvidence
    ).contains { $0.subject == "review-missing:evidence" })
    let unboundReviewEvidence = reportSource.replacingOccurrences(
        of: "digestValue(catalog.review.evidence)",
        with: "digestValue(.none)"
    )
    #expect(unboundReviewEvidence != reportSource)
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: modelSource + "\n" + claimsSource,
        reportSource: unboundReviewEvidence
    ).contains { $0.subject == "review-binding:evidence" })
    let inertReviewReference = reportSource.replacingOccurrences(
        of: "digestValue(catalog.review.evidence)",
        with: "catalog.review.evidence == nil ? .null : .null"
    )
    #expect(inertReviewReference != reportSource)
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: modelSource + "\n" + claimsSource,
        reportSource: inertReviewReference
    ).contains { $0.subject == "review-transformation:evidence" })
    let missingLawDiagnostic = reportSource.replacingOccurrences(
        of: "                    \"diagnostic\": diagnosticValue($0.diagnostic),\n",
        with: ""
    )
    #expect(missingLawDiagnostic != reportSource)
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: modelSource + "\n" + claimsSource,
        reportSource: missingLawDiagnostic
    ).contains { $0.subject == "lawObservations-missing:diagnostic" })
    let mismatchedLawDiagnostic = reportSource.replacingOccurrences(
        of: "diagnosticValue($0.diagnostic)",
        with: "diagnosticValue(.none)"
    )
    #expect(mismatchedLawDiagnostic != reportSource)
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: modelSource + "\n" + claimsSource,
        reportSource: mismatchedLawDiagnostic
    ).contains { $0.subject == "lawObservations-binding:diagnostic" })
    let missingMutationWorld = reportSource.replacingOccurrences(
        of: "                    \"mutant\": .string(observation.mutant.rawValue),\n                    \"world\": .string(observation.world.rawValue),\n",
        with: "                    \"mutant\": .string(observation.mutant.rawValue),\n"
    )
    #expect(missingMutationWorld != reportSource)
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: modelSource + "\n" + claimsSource,
        reportSource: missingMutationWorld
    ).contains { $0.subject == "mutationObservations-missing:world" })
    let unboundMutationWorld = reportSource.replacingOccurrences(
        of: "                    \"world\": .string(observation.world.rawValue),\n                    \"reached\":",
        with: "                    \"world\": .string(\"fixed\"),\n                    \"reached\":"
    )
    #expect(unboundMutationWorld != reportSource)
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: modelSource + "\n" + claimsSource,
        reportSource: unboundMutationWorld
    ).contains { $0.subject == "mutationObservations-binding:world" })
    let unboundFailureWorld = reportSource.replacingOccurrences(
        of: "\"world\": .string(world.rawValue)",
        with: "\"world\": .string(\"fixed\")"
    )
    #expect(unboundFailureWorld != reportSource)
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: modelSource + "\n" + claimsSource,
        reportSource: unboundFailureWorld
    ).contains { $0.subject == "failure-payload" })
    let swappedFailurePayloads = reportSource.replacingOccurrences(
        of: "case .survived(let mutant, let claim):",
        with: "case .survived(let claim, let mutant):"
    )
    #expect(swappedFailurePayloads != reportSource)
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: modelSource + "\n" + claimsSource,
        reportSource: swappedFailurePayloads
    ).contains { $0.subject == "failure-payload" })
    let duplicateFailureKind = reportSource.replacingOccurrences(
        of: ".string(\"baseline-crashed\")",
        with: ".string(\"baseline-test-failed\")"
    )
    #expect(duplicateFailureKind != reportSource)
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: modelSource + "\n" + claimsSource,
        reportSource: duplicateFailureKind
    ).contains { $0.subject == "failure-payload" })
    let escapedDuplicateFailureKind = reportSource.replacingOccurrences(
        of: ".string(\"baseline-crashed\")",
        with: ".string(\"baseline\\u{2D}test\\u{2D}failed\")"
    )
    #expect(escapedDuplicateFailureKind != reportSource)
    #expect(LawScanner.catalogSerializationViolations(
        modelSource: modelSource + "\n" + claimsSource,
        reportSource: escapedDuplicateFailureKind
    ).contains { $0.subject == "failure-payload" })
}

@Test
func worldSpaceIdentityAxesMatchModeledWorldDefinitions() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .path
    let worldData = try FileSystemBoundary.read(path: root + "/Sources/SwiftestModel/World.swift")
    let spaceData = try FileSystemBoundary.read(path: root + "/Sources/SwiftestEngine/WorldSpace.swift")
    guard let world = String(data: worldData, encoding: .utf8),
        let space = String(data: spaceData, encoding: .utf8) else {
        Issue.record("world sources have invalid UTF-8")
        return
    }
    #expect(LawScanner.worldSpaceAxisViolations(worldSource: world, worldSpaceSource: space).isEmpty)
    let wrongSelection = space.replacingOccurrences(
        of: "try encoder.appendRawAxis(\"build\", builds)",
        with: "try encoder.appendRawAxis(\"build\", locales)"
    )
    #expect(wrongSelection != space)
    #expect(LawScanner.worldSpaceAxisViolations(
        worldSource: world,
        worldSpaceSource: wrongSelection
    ).contains { $0.subject == "world-space-axis-binding:build" })
    let wrongIteratorSelection = space.replacingOccurrences(
        of: "build: cursor.take(space.builds)",
        with: "build: cursor.take(space.operatingSystems)"
    )
    #expect(wrongIteratorSelection != space)
    #expect(LawScanner.worldSpaceAxisViolations(
        worldSource: world,
        worldSpaceSource: wrongIteratorSelection
    ).contains { $0.subject == "world-iterator-axis" })
    let wrongBaseID = space.replacingOccurrences(
        of: "ordinal: UInt(position / plan.mutantCount)",
        with: "ordinal: UInt(position)"
    )
    #expect(wrongBaseID != space)
    #expect(LawScanner.worldSpaceAxisViolations(
        worldSource: world,
        worldSpaceSource: wrongBaseID
    ).contains { $0.subject == "world-iterator-axis" })
    let hiddenAxis = space.replacingOccurrences(
        of: "        try encoder.appendRawAxis(\"build\", builds)",
        with: "        if false { try encoder.appendRawAxis(\"build\", builds) }"
    )
    #expect(hiddenAxis != space)
    #expect(LawScanner.worldSpaceAxisViolations(
        worldSource: world,
        worldSpaceSource: hiddenAxis
    ).contains { $0.subject == "world-space-axis-shape" })
    let earlyReturn = space.replacingOccurrences(
        of: "        let mutantCount = try encoder.appendMutants(mutants)",
        with: "        if permissions.executionValues.count > 1 { return try encoder.plan(mutantCount: 1) }\n"
            + "        let mutantCount = try encoder.appendMutants(mutants)"
    )
    #expect(earlyReturn != space)
    #expect(LawScanner.worldSpaceAxisViolations(
        worldSource: world,
        worldSpaceSource: earlyReturn
    ).contains { $0.subject == "world-space-axis-shape" })
    let swappedAxes = space.replacingOccurrences(
        of: "        try encoder.appendRawAxis(\"build\", builds)\n"
            + "        try encoder.appendRawAxis(\"operating-system\", operatingSystems)",
        with: "        try encoder.appendRawAxis(\"operating-system\", operatingSystems)\n"
            + "        try encoder.appendRawAxis(\"build\", builds)"
    )
    #expect(swappedAxes != space)
    #expect(LawScanner.worldSpaceAxisViolations(
        worldSource: world,
        worldSpaceSource: swappedAxes
    ).contains { $0.subject == "world-iterator-axis" })
    let separateCount = space.replacingOccurrences(
        of: "        try axisPlan().count",
        with: "        try axisPlan().count.advanced()"
    )
    #expect(separateCount != space)
    #expect(LawScanner.worldSpaceAxisViolations(
        worldSource: world,
        worldSpaceSource: separateCount
    ).contains { $0.subject == "world-space-plan-sharing" })
    let incorrectDigit = space.replacingOccurrences(
        of: "stride /= values.count",
        with: "stride /= 1"
    )
    #expect(incorrectDigit != space)
    #expect(LawScanner.worldSpaceAxisViolations(
        worldSource: world,
        worldSpaceSource: incorrectDigit
    ).contains { $0.subject == "world-space-cursor-kernel" })
    let skippedOrdinal = space.replacingOccurrences(
        of: "CartesianCursor(total: plan.count.rawValue, ordinal: position)",
        with: "CartesianCursor(total: plan.count.rawValue, ordinal: position / 2)"
    )
    #expect(skippedOrdinal != space)
    #expect(LawScanner.worldSpaceAxisViolations(
        worldSource: world,
        worldSpaceSource: skippedOrdinal
    ).contains { $0.subject == "world-space-cursor-kernel" })
    let truncatedHandoff = space.replacingOccurrences(
        of: "WorldIterator(space: space, plan: plan)",
        with: "WorldIterator(space: space, plan: truncatedPlan)"
    )
    #expect(truncatedHandoff != space)
    #expect(LawScanner.worldSpaceAxisViolations(
        worldSource: world,
        worldSpaceSource: truncatedHandoff
    ).contains { $0.subject == "world-space-plan-handoff" })
    let mutablePlan = space.replacingOccurrences(
        of: "    private let plan: WorldAxisPlan",
        with: "    private var plan: WorldAxisPlan"
    )
    #expect(mutablePlan != space)
    #expect(LawScanner.worldSpaceAxisViolations(
        worldSource: world,
        worldSpaceSource: mutablePlan
    ).contains { $0.subject == "world-space-plan-handoff" })
    let brokenSkip = space.replacingOccurrences(
        of: "position = plan.count.rawValue",
        with: "position = 1"
    )
    #expect(brokenSkip != space)
    #expect(LawScanner.worldSpaceAxisViolations(
        worldSource: world,
        worldSpaceSource: brokenSkip
    ).contains { $0.subject == "world-space-cursor-kernel" })
    let hiddenConstruction = space.replacingOccurrences(
        of: "let world = World(",
        with: "let world = { World("
    ).replacingOccurrences(
        of: "mutant: cursor.take(space.mutants)\n        )",
        with: "mutant: cursor.take(space.mutants)\n        ) }()"
    )
    #expect(hiddenConstruction != space)
    #expect(LawScanner.worldSpaceAxisViolations(
        worldSource: world,
        worldSpaceSource: hiddenConstruction
    ).contains { $0.subject == "world-space-cursor-kernel" })
    let missingAxis = space.replacingOccurrences(
        of: "        try encoder.appendRawAxis(\"build\", builds)\n",
        with: ""
    )
    #expect(missingAxis != space)
    #expect(LawScanner.worldSpaceAxisViolations(
        worldSource: world,
        worldSpaceSource: missingAxis
    ).contains { $0.subject == "world-space-axis-shape" })
    let addedWorldField = world.replacingOccurrences(
        of: "public struct WorldDefinition: Hashable, Sendable {\n",
        with: "public struct WorldDefinition: Hashable, Sendable {\n    public let keyboard: BuildConfiguration\n"
    )
    #expect(addedWorldField != world)
    #expect(!LawScanner.worldSpaceAxisViolations(
        worldSource: addedWorldField,
        worldSpaceSource: space
    ).isEmpty)
}

@Test
func eventGenerationWitnessLawBindsObservationPersistenceAndAdvance() throws {
    guard let fixture = LawFixtureCatalog.all.first(where: { $0.law == .eventGenerationWitness }) else {
        Issue.record("missing event generation Law fixture")
        return
    }
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .path
    let sourcePath = "Sources/SwiftestPlatform/FileEventLease.swift"
    let sourceData = try FileSystemBoundary.read(path: root + "/" + sourcePath)
    let commandPath = "Sources/SwiftestCLI/SwiftestCommand.swift"
    let commandData = try FileSystemBoundary.read(path: root + "/" + commandPath)
    guard let source = String(data: sourceData, encoding: .utf8),
        let commandSource = String(data: commandData, encoding: .utf8) else {
        Issue.record("event witness sources have invalid UTF-8")
        return
    }
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-event-generation-law-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let relative = try ArtifactPath.parse(sourcePath)
    let commandRelative = try ArtifactPath.parse(commandPath)
    try FileSystemBoundary.write(
        sourceData,
        relativePath: relative,
        capability: scratch.issueWriteCapability()
    )
    try FileSystemBoundary.write(
        commandData,
        relativePath: commandRelative,
        capability: scratch.issueWriteCapability()
    )
    let legal = try LawScanner.scan(root: scratch.path)
    #expect(!legal.violations.contains { $0.law == .eventGenerationWitness })

    let verifiedArm = "                switch health.complete(continuity) {\n"
        + "                case .active(let active):\n"
        + "                    return active.witness\n"
        + "                case .invalid(let error):\n"
        + "                    throw error\n"
        + "                }"
    let mutations: [(String, String, String)] = [
        (fixture.legal, fixture.illegal, "observer-order"),
        (verifiedArm, "                return .initial", "verified-retention"),
        ("switch health.complete(continuity)", "switch health.snapshot", "verified-retention"),
        ("state = .active(next)", "state = .active(prior)", "witness-persistence"),
        ("generation.advanced()", "generation", "generation-advance"),
        ("state = .active(prior.including(observed))",
            "state = .active(FileEventHealth.initial.including(observed))",
            "completion-preservation"),
        ("first = firstAttributePath",
            "first = firstAttributePath == path ? firstAttributePath : path",
            "path-retention"),
        ("firstAttributePath: firstAttributePath)",
            "firstAttributePath: nil)",
            "path-completion"),
        ("throw .attributeAmbiguous(firstAttributePath)",
            "throw .attributeOriginMissing", "path-diagnostic"),
    ]
    for (original, replacement, subject) in mutations {
        #expect(source.contains(original))
        let mutant = source.replacingOccurrences(of: original, with: replacement)
        #expect(mutant != source)
        try FileSystemBoundary.write(
            Data(mutant.utf8),
            relativePath: relative,
            capability: scratch.issueWriteCapability()
        )
        let report = try LawScanner.scan(root: scratch.path)
        #expect(report.violations.contains {
            $0.law == .eventGenerationWitness && $0.subject == subject
        })
    }
    let observerEnd = "                continue\n            }\n        }\n    }\n\n    public borrowing func verifyUnchanged"
    #expect(source.contains(observerEnd))
    let deadObserver = source.replacingOccurrences(
        of: "        while true {\n",
        with: "        while true {\n            if false {\n"
    ).replacingOccurrences(
        of: observerEnd,
        with: "                continue\n            }\n            }\n            return .initial\n        }\n    }\n\n    public borrowing func verifyUnchanged"
    )
    #expect(deadObserver != source)
    #expect(deadObserver.contains("            return .initial\n        }\n    }"))
    try FileSystemBoundary.write(
        Data(deadObserver.utf8),
        relativePath: relative,
        capability: scratch.issueWriteCapability()
    )
    let deadReport = try LawScanner.scan(root: scratch.path)
    #expect(deadReport.violations.contains {
        $0.law == .eventGenerationWitness && $0.subject == "observer-order"
    })
    try FileSystemBoundary.write(
        sourceData,
        relativePath: relative,
        capability: scratch.issueWriteCapability()
    )
    let continuityOnly = commandSource.replacingOccurrences(
        of: "guard finalInput == reportInput else",
        with: "guard finalInput.continuity == reportInput.continuity else"
    )
    #expect(continuityOnly != commandSource)
    try FileSystemBoundary.write(
        Data(continuityOnly.utf8),
        relativePath: commandRelative,
        capability: scratch.issueWriteCapability()
    )
    let report = try LawScanner.scan(root: scratch.path)
    #expect(report.violations.contains {
        $0.law == .eventGenerationWitness && $0.subject == "prepublication-witness"
    })
}

@Test
func commentOnlySwiftFilesStillFailTheLaw() {
    let path = "Sources/SwiftestFaults/InsertedViolation.swift"
    for source in ["// gate-probe\n", "/* gate-probe */\n", "/// gate-probe\n"] {
        #expect(LawScanner.scanSwiftSource(source, path: path).contains {
            $0.law == .forbiddenComment && $0.location.line == 1 && $0.location.column == 1
        })
    }
}

@Test
func boundaryExemptionsRequireExactSourcePaths() {
    let forgedPlatform = "Sources/SwiftestEngine/Nested/Sources/SwiftestPlatform/Unsafe.swift"
    let directProcess = LawScanner.scanSwiftSource("Process()", path: forgedPlatform)
    #expect(directProcess.contains { $0.law == .rawProcess })
    let forgedABI = "Sources/SwiftestEngine/SwiftestPlatform/ABIAdapter.swift"
    let directUnsafe = LawScanner.scanSwiftSource("withUnsafeBytes(of: value) { body($0) }", path: forgedABI)
    #expect(directUnsafe.contains { $0.law == .unsafeOutsideBoundary })
    let forgedTesting = "Sources/SwiftestEngine/SwiftestTesting/Macros.swift"
    let existential = LawScanner.scanSwiftSource("let value: any Service", path: forgedTesting)
    #expect(existential.contains { $0.law == .ownedExistential })
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
