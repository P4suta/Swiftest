import Foundation
@testable import SwiftestLaws
import SwiftestModel
import SwiftestPlatform
import Testing

private let pinnedLakefile = "name = \"swiftest\"\n"
    + "version = \"0.1.0\"\n"
    + "defaultTargets = [\"SwiftestProofs\", \"swiftest-proof-oracle\"]\n"
    + "\n"
    + "[[lean_lib]]\n"
    + "name = \"SwiftestProofs\"\n"
    + "\n"
    + "[[lean_exe]]\n"
    + "name = \"swiftest-proof-oracle\"\n"
    + "root = \"SwiftestProofs.Oracle\"\n"

private let pinnedLakeManifest = "{\"version\":\"1.2.0\",\"packagesDir\":\".lake/packages\","
    + "\"packages\":[],\"name\":\"swiftest\",\"lakeDir\":\".lake\",\"fixedToolchain\":false}"

@Test
func leanTrustLexerDistinguishesProofTokensFromStringsAndComments() throws {
    let legal = "def text := \"sorry admit axiom sorryAx constant native_decide opaque\"\n"
        + "def nested := \"escaped \\\"sorry\\\"\"\n"
        + "def axiomName := 1\n"
        + "def not_sorry := 2\n"
        + "def sorryAxial := 3\n"
        + "/- sorry /- admit -/ axiom constant native_decide -/\n"
        + "-- sorryAx unsafe opaque\n"
    try LeanTrust.inspectSource(legal, path: "Fixture.lean")
}

@Test
func leanTrustRejectsQuotedIdentifierProofHole() {
    let attacks = [
        ("set_option warn.«sorry» false in\n", 17),
        ("theorem fabricated : False := «sorryAx» False false\n", 31),
    ]
    for (source, column) in attacks {
        do {
            try LeanTrust.inspectSource(source, path: "Fixture.lean")
            Issue.record("accepted quoted Lean proof hole")
        } catch let error {
            #expect(error == .quotedIdentifier(SourceLocation(file: "Fixture.lean", line: 1, column: column)))
        }
    }
    do {
        try LeanTrust.inspectSource("def «safeName» := 4\n", path: "Fixture.lean")
        Issue.record("accepted quoted Lean identifier outside the proof hole")
    } catch let error {
        #expect(error == .quotedIdentifier(SourceLocation(file: "Fixture.lean", line: 1, column: 5)))
    }
}

@Test
func leanTrustRejectsRawStringBeforeItCanHideAnAxiom() throws {
    let hiddenAxiom = #"""
    def marker := r"\"
    axiom hidden : False
    def trailing := "\""
    """# + "\n"
    for source in [hiddenAxiom, "def marker := r###\"safe\"###\n"] {
        do {
            try LeanTrust.inspectSource(source, path: "Fixture.lean")
            Issue.record("accepted unsupported Lean raw string")
        } catch let error {
            #expect(error == .unsupportedRawString(SourceLocation(file: "Fixture.lean", line: 1, column: 15)))
        }
    }
    let ordinaryString = #"""
    def marker := "r\"safe\""
    """# + "\n"
    try LeanTrust.inspectSource(ordinaryString, path: "Fixture.lean")
}

@Test
func leanCommentScannerRejectsRawStringBeforeItCanHideAComment() {
    let source = #"""
    def marker := r"\"
    -- hidden comment
    def trailing := "\""
    """# + "\n"
    let scan = OtherSourceLexer.scan(in: source, flavor: .lean)
    #expect(scan.unsupportedLeanRawStringOffset == 14)
    #expect(scan.comments.isEmpty)
    let ordinaryString = #"""
    def marker := "r\"safe\""
    -- visible comment
    """# + "\n"
    let ordinary = OtherSourceLexer.scan(in: ordinaryString, flavor: .lean)
    #expect(ordinary.unsupportedLeanRawStringOffset == nil)
    #expect(ordinary.comments.map(\.text) == ["-- visible comment"])
}

@Test
func leanTrustLexerRejectsEveryStandaloneProofHole() {
    for token in [
        "sorry", "admit", "axiom", "sorryAx", "constant", "opaque", "unsafe",
        "native", "native_decide", "bv_decide", "implemented_by", "trustCompiler",
        "reduceBool", "reduceNat", "ofReduceBool", "ofReduceNat", "partial",
        "partial_fixpoint", "macro", "syntax", "elab", "elab_rules", "run_tac",
    ] {
        let source = "def text := \"axiom\"\nby " + token + "\n"
        do {
            try LeanTrust.inspectSource(source, path: "Fixture.lean")
            Issue.record("accepted forbidden Lean token \(token)")
        } catch let error {
            #expect(error == .proofHole(
                SourceLocation(file: "Fixture.lean", line: 2, column: 4),
                token
            ))
        }
    }
}

@Test
func leanTrustLexerRejectsUnterminatedLexicalForms() {
    do {
        try LeanTrust.inspectSource("def text := \"sorry", path: "Fixture.lean")
        Issue.record("accepted unterminated Lean string")
    } catch let error {
        #expect(error == .unterminatedString("Fixture.lean"))
    }
    do {
        try LeanTrust.inspectSource("/- axiom", path: "Fixture.lean")
        Issue.record("accepted unterminated Lean comment")
    } catch let error {
        #expect(error == .unterminatedComment("Fixture.lean"))
    }
    do {
        try LeanTrust.inspectSource("def «sorry", path: "Fixture.lean")
        Issue.record("accepted unterminated quoted Lean identifier")
    } catch let error {
        #expect(error == .unterminatedQuotedIdentifier("Fixture.lean"))
    }
}

@Test
func leanTrustAuditRejectsInjectedAxiomInProofTree() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-lean-trust-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let root = try ArtifactPath.parse("SwiftestProofs.lean")
    let safe = try ArtifactPath.parse("SwiftestProofs/Safe.lean")
    let bad = try ArtifactPath.parse("SwiftestProofs/Bad.lean")
    let lakefile = try ArtifactPath.parse("lakefile.toml")
    let toolchain = try ArtifactPath.parse("lean-toolchain")
    try FileSystemBoundary.write(Data(pinnedLakefile.utf8), relativePath: lakefile, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.write(Data("leanprover/lean4:v4.34.1\n".utf8), relativePath: toolchain, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.write(Data("import SwiftestProofs.Safe\n".utf8), relativePath: root, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.write(Data("def safe := \"sorry\"\n".utf8), relativePath: safe, capability: scratch.issueWriteCapability())
    try LeanTrust.audit(root: scratch.path)
    try FileSystemBoundary.write(Data("axiom bad : True\n".utf8), relativePath: bad, capability: scratch.issueWriteCapability())
    do {
        try LeanTrust.audit(root: scratch.path)
        Issue.record("accepted injected Lean axiom")
    } catch let error {
        #expect(error == .proofHole(
            SourceLocation(file: "SwiftestProofs/Bad.lean", line: 1, column: 1),
            "axiom"
        ))
    }
}

@Test
func leanTrustRejectsExternalLakeRequirementAndToolchainDrift() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-lake-config-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let lakefile = try ArtifactPath.parse("lakefile.toml")
    let toolchain = try ArtifactPath.parse("lean-toolchain")
    let injected = pinnedLakefile + "\n[[require]]\nname = \"external\"\n"
    try FileSystemBoundary.write(Data(injected.utf8), relativePath: lakefile, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.write(Data("leanprover/lean4:v4.34.1\n".utf8), relativePath: toolchain, capability: scratch.issueWriteCapability())
    do {
        try LeanTrust.audit(root: scratch.path)
        Issue.record("accepted external Lake requirement")
    } catch let error {
        #expect(error == .lakeConfiguration("lakefile.toml"))
    }
    try FileSystemBoundary.write(Data(pinnedLakefile.utf8), relativePath: lakefile, capability: scratch.issueWriteCapability())
    try FileSystemBoundary.write(Data("leanprover/lean4:v4.35.0\n".utf8), relativePath: toolchain, capability: scratch.issueWriteCapability())
    do {
        try LeanTrust.audit(root: scratch.path)
        Issue.record("accepted changed Lean toolchain")
    } catch let error {
        #expect(error == .lakeConfiguration("lean-toolchain"))
    }
}

@Test
func leanTrustManifestRequiresClosedDependencySetAndStrictJSON() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-lake-manifest-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let manifest = try ArtifactPath.parse("lake-manifest.json")
    try FileSystemBoundary.write(Data(pinnedLakeManifest.utf8), relativePath: manifest, capability: scratch.issueWriteCapability())
    try LeanTrust.auditManifest(root: scratch.path)
    let package = pinnedLakeManifest.replacingOccurrences(of: "\"packages\":[]", with: "\"packages\":[{\"name\":\"external\"}]")
    try FileSystemBoundary.write(Data(package.utf8), relativePath: manifest, capability: scratch.issueWriteCapability())
    do {
        try LeanTrust.auditManifest(root: scratch.path)
        Issue.record("accepted external Lake package")
    } catch let error {
        #expect(error == .lakeManifestMismatch)
    }
    let unknown = pinnedLakeManifest.replacingOccurrences(of: "\"packages\":[]", with: "\"packages\":[],\"extension\":1")
    try FileSystemBoundary.write(Data(unknown.utf8), relativePath: manifest, capability: scratch.issueWriteCapability())
    do {
        try LeanTrust.auditManifest(root: scratch.path)
        Issue.record("accepted unknown Lake manifest field")
    } catch let error {
        #expect(error == .lakeManifestMismatch)
    }
    let duplicate = pinnedLakeManifest.replacingOccurrences(of: "\"packages\":[]", with: "\"packages\":[],\"packages\":[]")
    try FileSystemBoundary.write(Data(duplicate.utf8), relativePath: manifest, capability: scratch.issueWriteCapability())
    do {
        try LeanTrust.auditManifest(root: scratch.path)
        Issue.record("accepted duplicate Lake manifest key")
    } catch let error {
        if case .lakeManifestCodec(.duplicateKey(_, "packages")) = error {
            #expect(true)
        } else {
            Issue.record("wrong duplicate key diagnostic: \(error)")
        }
    }
}

@Test
func checkedInLeanProofSourcesPassTheTrustGate() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .path
    try LeanTrust.audit(root: root)
}
