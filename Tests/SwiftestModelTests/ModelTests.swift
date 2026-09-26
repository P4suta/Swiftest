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
}

@Test
func pipelineReachesAuditedOnlyThroughEveryState() throws {
    let discovery = DiscoveryCatalog(
        preservationClaims: [],
        detectionClaims: [],
        tests: [try TestID.parse("test-1")]
    )
    let plan = FrozenPlan(
        run: try RunID.parse("run-1"),
        worlds: [],
        mutants: [],
        digest: try Digest.sha256(Data("plan".utf8))
    )
    let discovered = Pipeline<Discovered>.discover(discovery)
    let planned = try discovered.plan()
    let frozen = planned.freeze(plan)
    let built = try frozen.built()
    let baseline = built.baselinePassed()
    let executed = baseline.executed()
    let recorded = executed.record(try catalog(failures: []))
    let audited = try recorded.audit()
    let closed = try audited.closedCatalog()
    #expect(closed.verdict == .assured)
}

private func catalog(failures: [ExecutionFailure]) throws -> EvidenceCatalog {
    EvidenceCatalog(
        run: try RunID.parse("run-model"),
        scope: .complete,
        preservationClaims: [],
        detectionClaims: [],
        worlds: [],
        mutants: [],
        claimObservations: [],
        mutationObservations: [],
        lawObservations: [LawObservation(code: "laws", status: .passed)],
        schemaObservations: [SchemaObservation(version: .v1, status: .passed)],
        failures: failures,
        review: IndependentReview(
            status: .accepted,
            evidence: try Digest.sha256(Data("review".utf8))
        ),
        executionCount: try EvidenceCount.nonnegative(1)
    )
}
