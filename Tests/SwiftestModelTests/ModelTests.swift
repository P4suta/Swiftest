import CryptoKit
import Foundation
import SwiftestModel
import Testing

@Test
func nominalValuesRejectInvalidInputAndDigestCanonically() throws {
    let run = try RunID.parse("run-1")
    #expect(run.rawValue == "run-1")
    do {
        let invalid = try RunID.parse("")
        Issue.record("unexpected identifier")
        #expect(invalid.rawValue.isEmpty)
    } catch let error {
        #expect(error == .empty)
    }
    let digest = try Digest.sha256(Data("abc".utf8))
    #expect(digest.rawValue == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}

@Test
func artifactPathsRejectAliasesAndTraversal() throws {
    for (input, expected) in [
        ("a/../b", ArtifactPathError.parentTraversal),
        ("a/./b", .selfTraversal),
        ("a//b", .emptySegment),
        ("a/", .emptySegment),
    ] {
        do {
            let path = try ArtifactPath.parse(input)
            Issue.record("noncanonical path was accepted")
            #expect(path.rawValue.isEmpty)
        } catch let error {
            #expect(error == expected)
        }
    }
}

@Test
func artifactPathOracleCoversEveryRejectionKind() {
    let lines = ArtifactPathOracle.text().split(separator: "\n")
    #expect(lines.count == 9)
    #expect(lines.first == "path\tempty\tempty")
    #expect(lines.last == "path\tplain\taccepted")
}

@Test
func firstPartySHA256MatchesAppleAcrossBlockBoundaries() throws {
    for length in [0, 1, 55, 56, 63, 64, 65, 127, 128, 129, 1024] {
        let bytes = (0..<length).map { UInt8($0 % 251) }
        let data = Data(bytes)
        let reference = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let observed = try Digest.sha256(data)
        #expect(observed.rawValue == reference)
    }
}

@Test
func auditSeparatesInvalidGapsAndUnsettled() throws {
    let assured = try AuditKernel.close(catalog(failures: []))
    #expect(assured.verdict == .assured)
    let gap = try AuditKernel.close(catalog(failures: [
        .mutant(.notReached(try MutantID.parse("mutant-1")))
    ]))
    #expect(gap.verdict == .gaps)
    let unsettled = try AuditKernel.close(catalog(failures: [
        .clean(.baselineTestFailed(try TestID.parse("test-1"), try WorldID.parse("world-1")))
    ]))
    #expect(unsettled.verdict == .unsettled)
    let invalid = try AuditKernel.close(catalog(failures: [
        .apparatus(.toolchain(Diagnostic(
            code: .apparatusFailed,
            subject: "toolchain",
            detail: "mismatch"
        )))
    ]))
    #expect(invalid.verdict == .invalid)
    #expect(invalid.diagnostics.contains(Diagnostic(
        code: .apparatusFailed,
        subject: "toolchain",
        detail: "mismatch"
    )))
    #expect(gap.diagnostics.contains(where: { $0.code == .mutationUnreached }))
    #expect(unsettled.diagnostics.contains(where: { $0.code == .baselineFailed }))
}

@Test
func pipelineReachesAuditedOnlyThroughEveryState() throws {
    let evidence = try catalog(failures: [])
    let discovery = DiscoveryCatalog(
        preservationClaims: evidence.preservationClaims,
        detectionClaims: evidence.detectionClaims,
        tests: [try TestID.parse("test-1")]
    )
    let plan = FrozenPlan(
        run: evidence.run,
        worlds: evidence.worlds,
        mutants: evidence.mutants,
        digest: try Digest.sha256(Data("plan".utf8))
    )
    let discovered = Pipeline<Discovered>.discover(discovery)
    let planned = try discovered.plan()
    let frozen = planned.freeze(plan)
    let built = try frozen.built()
    let baseline = built.baselinePassed()
    let executed = baseline.executed()
    let recorded = executed.record(evidence)
    let audited = try recorded.audit()
    let closed = try audited.closedCatalog()
    #expect(closed.verdict == .assured)
}

@Test
func pipelineRejectsEvidenceThatDiffersFromFrozenPlan() throws {
    let evidence = try catalog(failures: [])
    let discovery = DiscoveryCatalog(
        preservationClaims: evidence.preservationClaims,
        detectionClaims: evidence.detectionClaims,
        tests: [try TestID.parse("test-1")]
    )
    let plan = FrozenPlan(
        run: try RunID.parse("different-run"),
        worlds: evidence.worlds,
        mutants: evidence.mutants,
        digest: try Digest.sha256(Data("plan".utf8))
    )
    let discovered = Pipeline<Discovered>.discover(discovery)
    let planned = try discovered.plan()
    let frozen = planned.freeze(plan)
    let built = try frozen.built()
    let baseline = built.baselinePassed()
    let executed = baseline.executed()
    let recorded = executed.record(evidence)
    do {
        let audited = try recorded.audit()
        let closed = try audited.closedCatalog()
        Issue.record("mismatched plan was accepted")
        #expect(closed.verdict == .invalid)
    } catch let error {
        #expect(error == .planMismatch(.run))
    }
}

@Test
func emptyEvidenceCannotProduceAssuredVerdict() throws {
    let empty = EvidenceCatalog(
        run: try RunID.parse("run-empty"),
        scope: .complete,
        preservationClaims: [],
        detectionClaims: [],
        worlds: [],
        mutants: [],
        claimObservations: [],
        mutationObservations: [],
        lawObservations: LawCode.allCases.map { LawObservation(code: $0, status: .passed) },
        schemaObservations: [SchemaObservation(version: .v2, status: .passed)],
        failures: [],
        review: IndependentReview(status: .pending, evidence: nil),
        executionCount: try EvidenceCount.nonnegative(0)
    )
    let audited = try AuditKernel.close(empty)
    #expect(audited.verdict == .gapsAndUnsettled)
    #expect(audited.diagnostics.contains(where: { $0.code == .reviewMissing }))
    #expect(audited.diagnostics.contains(where: { $0.subject == "tests" }))
}

@Test
func auditRequiresEveryClosedLawExactlyOnce() throws {
    guard let finalLaw = LawCode.allCases.last, let firstLaw = LawCode.allCases.first else {
        Issue.record("closed law domain was empty")
        return
    }
    let incomplete = try catalog(
        failures: [],
        lawObservations: LawCode.allCases.dropLast().map { LawObservation(code: $0, status: .passed) }
    )
    do {
        let audited = try AuditKernel.close(incomplete)
        Issue.record("missing law was accepted")
        #expect(audited.verdict == .invalid)
    } catch let error {
        #expect(error == .missingLawObservation(finalLaw))
    }
    let repeated = try catalog(
        failures: [],
        lawObservations: LawCode.allCases.map { LawObservation(code: $0, status: .passed) }
            + [LawObservation(code: firstLaw, status: .passed)]
    )
    do {
        let audited = try AuditKernel.close(repeated)
        Issue.record("duplicate law was accepted")
        #expect(audited.verdict == .invalid)
    } catch let error {
        #expect(error == .duplicateLawObservation(firstLaw))
    }
}

@Test
func unprovenClaimIrrelevanceCannotProduceAssuredVerdict() throws {
    let base = try catalog(failures: [])
    for unproven in base.claimObservations {
        let observations = base.claimObservations.map { observation in
            ClaimObservation(
                claim: observation.claim,
                world: observation.world,
                status: observation.claim == unproven.claim ? .provenIrrelevant : .passed,
                diagnostic: nil
            )
        }
        let evidence = EvidenceCatalog(
            run: base.run,
            scope: base.scope,
            preservationClaims: base.preservationClaims,
            detectionClaims: base.detectionClaims,
            worlds: base.worlds,
            mutants: base.mutants,
            claimObservations: observations,
            mutationObservations: base.mutationObservations,
            lawObservations: base.lawObservations,
            schemaObservations: base.schemaObservations,
            failures: base.failures,
            review: base.review,
            executionCount: base.executionCount
        )
        let audited = try AuditKernel.close(evidence)
        #expect(audited.verdict == .gaps)
        #expect(audited.diagnostics.contains(where: {
            $0.subject == unproven.claim.rawValue + ":" + unproven.world.rawValue
        }))
    }
}

private func catalog(
    failures: [ExecutionFailure],
    lawObservations: [LawObservation] = LawCode.allCases.map { LawObservation(code: $0, status: .passed) }
) throws -> EvidenceCatalog {
    let preservation = try ClaimID.parse("preservation-1")
    let detection = try ClaimID.parse("detection-1")
    let world = try WorldID.parse("world-1")
    let mutant = try MutantID.parse("mutant-1")
    return EvidenceCatalog(
        run: try RunID.parse("run-model"),
        scope: .complete,
        preservationClaims: [preservation],
        detectionClaims: [detection],
        worlds: [world],
        mutants: [mutant],
        claimObservations: [
            ClaimObservation(claim: preservation, world: world, status: .passed, diagnostic: nil),
            ClaimObservation(claim: detection, world: world, status: .passed, diagnostic: nil),
        ],
        mutationObservations: [MutationObservation(
            mutant: mutant,
            reached: .passed,
            infected: .passed,
            detected: .passed
        )],
        lawObservations: lawObservations,
        schemaObservations: [SchemaObservation(version: .v2, status: .passed)],
        failures: failures,
        review: IndependentReview(
            status: .accepted,
            evidence: try Digest.sha256(Data("review".utf8))
        ),
        executionCount: try EvidenceCount.nonnegative(1)
    )
}
