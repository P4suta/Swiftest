import Foundation
import SwiftestCodec
import SwiftestDecision
import SwiftestFaults
import SwiftestModel
import SwiftestReport
import SwiftestScore
import Testing

@Test
func structurallyAuditedFaultsCannotAssureUnobservedBehavior() throws {
    let closed = try AuditKernel.close(try catalog(executionCount: 3))
    let faults = try faultAudit()
    let report = try AssuredReport(catalog: closed, faults: faults)
    let envelope = try ReportCodec.decodeEnvelope(ReportCodec.encode(report))
    #expect(report.verdict == .gaps)
    #expect(envelope.faultStatus == .structural)
    #expect(envelope.faultScenarioCount?.rawValue == 29)
    #expect(envelope.injectedFaultCount?.rawValue == 34)
    #expect(envelope.faultDigest == faults.digest)
    #expect(envelope.diagnostics.contains { $0.subject == "fault-behavior" })
}

@Test
func unverifiedFaultsCannotCarryAssuredVerdict() throws {
    let closed = try AuditKernel.close(try catalog(executionCount: 1))
    let report = try AssuredReport(catalog: closed, faultEvidence: .unverified)
    #expect(closed.verdict == .assured)
    #expect(report.verdict == .gaps)
    let envelope = try ReportCodec.decodeEnvelope(ReportCodec.encode(report))
    #expect(envelope.verdict == .gaps)
    #expect(envelope.faultStatus == .unverified)
    #expect(envelope.faultDigest == nil)
    #expect(envelope.injectedFaultCount == nil)
    #expect(envelope.diagnostics.contains(where: { $0.subject == "faults" }))
    let decoded = try StrictJSON.decode(ReportCodec.encode(report))
    guard case .object(var fields) = decoded else {
        Issue.record("report was not an object")
        return
    }
    fields["verdict"] = .string(Verdict.assured.rawValue)
    do {
        let invalid = try ReportCodec.decodeEnvelope(StrictJSON.encode(.object(fields)))
        Issue.record("unverified fault evidence was upgraded")
        #expect(invalid.verdict == .invalid)
    } catch let error {
        #expect(error == .decisionMismatch(expected: .gapsAndUnsettled, actual: .assured))
    }
}

@Test
func strictReportEnvelopeRejectsUnknownFields() throws {
    let report = try AssuredReport(
        catalog: AuditKernel.close(try catalog(executionCount: 1)),
        faultEvidence: .unverified
    )
    let encoded = try ReportCodec.encode(report)
    let decoded = try SwiftestCodec.StrictJSON.decode(encoded)
    guard case .object(var fields) = decoded else {
        Issue.record("report was not an object")
        return
    }
    fields["extra"] = .null
    do {
        let envelope = try ReportCodec.decodeEnvelope(SwiftestCodec.StrictJSON.encode(.object(fields)))
        Issue.record("unknown field accepted")
        #expect(envelope.run.rawValue.isEmpty)
    } catch let error {
        #expect(error == .codec(.unknownField("extra")))
    }
}

@Test
func strictReportEnvelopeRejectsImpossibleCounts() throws {
    let report = try AssuredReport(
        catalog: AuditKernel.close(try catalog(executionCount: 1)),
        faultEvidence: .unverified
    )
    let decoded = try StrictJSON.decode(ReportCodec.encode(report))
    guard case .object(var fields) = decoded else {
        Issue.record("report was not an object")
        return
    }
    fields["score"] = .object(["passed": .number("2"), "total": .number("1")])
    do {
        let envelope = try ReportCodec.decodeEnvelope(StrictJSON.encode(.object(fields)))
        Issue.record("impossible score was accepted")
        #expect(envelope.scorePassed == .zero)
    } catch let error {
        #expect(error == .invalidScore(
            try EvidenceCount.nonnegative(2),
            try EvidenceCount.nonnegative(1)
        ))
    }
    fields["score"] = .object(["passed": .number("1"), "total": .number("2")])
    let faults = try faultAudit()
    fields["faults"] = .object([
        "status": .string("structural"),
        "digest": .string(faults.digest.rawValue),
        "injectedPoints": .number("0"),
        "scenarios": .number("29"),
    ])
    do {
        let envelope = try ReportCodec.decodeEnvelope(StrictJSON.encode(.object(fields)))
        Issue.record("empty fault summary was accepted")
        #expect(envelope.injectedFaultCount == nil)
    } catch let error {
        #expect(error == .invalidFaultSummary(
            try EvidenceCount.nonnegative(29),
            EvidenceCount.zero
        ))
    }
}

@Test
func reportSchemaDeclaresEveryEncodedScoreField() throws {
    let report = try AssuredReport(
        catalog: AuditKernel.close(try catalog(executionCount: 1)),
        faultEvidence: .unverified
    )
    guard case .object(let schemaRoot) = ReportCodec.schema(),
        case .object(let schemaFields)? = schemaRoot["properties"],
        case .object(let scoreSchema)? = schemaFields["score"],
        case .object(let scoreFields)? = scoreSchema["properties"],
        case .object(let encodedRoot) = try StrictJSON.decode(ReportCodec.encode(report)),
        case .object(let encodedScore)? = encodedRoot["score"] else {
        Issue.record("score schema and encoded report were not objects")
        return
    }
    #expect(Set(scoreFields.keys) == Set(encodedScore.keys))
    #expect(scoreFields["passed"] == .object([
        "minimum": .number("0"),
        "type": .string("integer"),
    ]))
    #expect(scoreFields["total"] == .object([
        "minimum": .number("0"),
        "type": .string("integer"),
    ]))
}

@Test
func executionVolumeCannotChangeScoreOrVerdict() throws {
    let first = try catalog(executionCount: 1)
    let second = try catalog(executionCount: 999)
    let firstSignals = VerdictDecision.signals(for: first)
    let secondSignals = VerdictDecision.signals(for: second)
    #expect(VerdictDecision.decide(firstSignals) == VerdictDecision.decide(secondSignals))
    #expect(try AssuranceScore.measure(first) == AssuranceScore.measure(second))
}

@Test
func unprovenIrrelevanceCannotIncreaseScore() throws {
    let evidence = try catalog(executionCount: 1, claimStatus: .provenIrrelevant)
    let score = try AssuranceScore.measure(evidence)
    #expect(score.passed.rawValue + 1 == score.total.rawValue)
    let audited = try AuditKernel.close(evidence)
    #expect(audited.verdict == .gaps)
}

@Test
func catalogDigestBindsFailureEvidence() throws {
    let cleanReport = try AssuredReport(
        catalog: AuditKernel.close(try catalog(executionCount: 1)),
        faultEvidence: .unverified
    )
    let failedReport = try AssuredReport(
        catalog: AuditKernel.close(try catalog(
            executionCount: 1,
            failures: [.clean(.baselineTestFailed(
                try TestID.parse("swift-package-suite"),
                try WorldID.parse("world-1")
            ))]
        )),
        faultEvidence: .unverified
    )
    let clean = try ReportCodec.decodeEnvelope(ReportCodec.encode(cleanReport))
    let failed = try ReportCodec.decodeEnvelope(ReportCodec.encode(failedReport))
    #expect(clean.catalogDigest != failed.catalogDigest)
    #expect(clean.verdict == .gaps)
    #expect(failed.verdict == .gapsAndUnsettled)
}

@Test
func swiftVerdictOracleIsExhaustiveAndStable() {
    let lines = VerdictOracle.text().split(separator: "\n")
    #expect(lines.count == 24)
    #expect(lines.first == "absent\tabsent\tabsent\tcomplete\tASSURED")
    #expect(lines.last == "present\tpresent\tpresent\tscoped\tINVALID")
    let reportLines = ReportVerdictOracle.text().split(separator: "\n")
    #expect(reportLines.count == 21)
    #expect(reportLines.first == "report\tASSURED\tverified\tASSURED")
    #expect(reportLines.last == "report\tINVALID\tunverified\tINVALID")
}

private func catalog(
    executionCount: Int,
    failures: [ExecutionFailure] = [],
    claimStatus: ObservationStatus = .passed
) throws -> EvidenceCatalog {
    let preservation = try ClaimID.parse("preservation-1")
    let detection = try ClaimID.parse("detection-1")
    let world = try WorldID.parse("world-1")
    let mutant = try MutantID.parse("mutant-1")
    let laws = LawCode.allCases.map { LawObservation(code: $0, status: .passed) }
    return EvidenceCatalog(
        run: try RunID.parse("run-report"),
        scope: .complete,
        preservationClaims: [preservation],
        detectionClaims: [detection],
        worlds: [world],
        mutants: [mutant],
        claimObservations: [
            ClaimObservation(claim: preservation, world: world, status: claimStatus, diagnostic: nil),
            ClaimObservation(claim: detection, world: world, status: .passed, diagnostic: nil),
        ],
        mutationObservations: [MutationObservation(
            mutant: mutant,
            reached: .passed,
            infected: .passed,
            detected: .passed
        )],
        lawObservations: laws,
        schemaObservations: [SchemaObservation(version: .v2, status: .passed)],
        failures: failures,
        review: IndependentReview(
            status: .accepted,
            evidence: try Digest.sha256(Data("review".utf8))
        ),
        executionCount: try EvidenceCount.nonnegative(executionCount)
    )
}

private func faultAudit() throws -> AuditedFaultCampaign {
    let campaign = try StandardFaultCampaign.make()
    let transcript = FaultCampaignExecutor.execute(campaign: campaign) { scenario, injector in
        var observed: [FaultActivationObservation] = []
        for point in campaign.points {
            let evaluation = FaultInjectionBoundary.evaluate(
                point: point.id,
                injector: &injector,
                operation: { point.id }
            )
            if case .injected(let activated, _) = evaluation {
                observed.append(FaultActivationObservation(
                    point: activated,
                    result: point.expectation == .recover ? .recovered : .failedClosed
                ))
            }
        }
        return scenario.kind == .clean ? .cleanPassed : .handled(observed)
    }
    return try FaultAuditKernel.close(
        campaign: campaign,
        transcript: transcript
    )
}
