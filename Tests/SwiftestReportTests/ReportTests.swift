import Foundation
import SwiftestCodec
import SwiftestDecision
import SwiftestFaults
import SwiftestModel
import SwiftestReport
import SwiftestScore
import Testing

@Test
func assuredReportRequiresAndCarriesClosedFaultEvidence() throws {
    let closed = try AuditKernel.close(try catalog(executionCount: 3))
    let faults = try faultAudit()
    let report = try AssuredReport(catalog: closed, faults: faults)
    let encoded = try ReportCodec.encode(report)
    let envelope = try ReportCodec.decodeEnvelope(encoded)
    #expect(envelope.verdict == .assured)
    #expect(envelope.faultScenarioCount.rawValue == 29)
    #expect(envelope.injectedFaultCount.rawValue == 34)
    #expect(envelope.faultDigest == faults.digest)
}

@Test
func strictReportEnvelopeRejectsUnknownFields() throws {
    let report = try AssuredReport(
        catalog: AuditKernel.close(try catalog(executionCount: 1)),
        faults: faultAudit()
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
func scoreAndExecutionVolumeCannotChangeVerdict() throws {
    let first = try catalog(executionCount: 1)
    let second = try catalog(executionCount: 999)
    let firstSignals = VerdictDecision.signals(for: first)
    let secondSignals = VerdictDecision.signals(for: second)
    #expect(VerdictDecision.decide(firstSignals) == VerdictDecision.decide(secondSignals))
    #expect(try AssuranceScore.measure(first).total != AssuranceScore.measure(second).total)
}

@Test
func swiftVerdictOracleIsExhaustiveAndStable() {
    let lines = VerdictOracle.text().split(separator: "\n")
    #expect(lines.count == 24)
    #expect(lines.first == "absent\tabsent\tabsent\tcomplete\tASSURED")
    #expect(lines.last == "present\tpresent\tpresent\tscoped\tINVALID")
}

private func catalog(executionCount: Int) throws -> EvidenceCatalog {
    let laws = executionCount == 1
        ? [LawObservation(code: "laws", status: .passed)]
        : [
            LawObservation(code: "laws", status: .passed),
            LawObservation(code: "fault-laws", status: .passed),
        ]
    return EvidenceCatalog(
        run: try RunID.parse("run-report"),
        scope: .complete,
        preservationClaims: [],
        detectionClaims: [],
        worlds: [],
        mutants: [],
        claimObservations: [],
        mutationObservations: [],
        lawObservations: laws,
        schemaObservations: [SchemaObservation(version: .v1, status: .passed)],
        failures: [],
        review: IndependentReview(
            status: .accepted,
            evidence: try Digest.sha256(Data("review".utf8))
        ),
        executionCount: try EvidenceCount.nonnegative(executionCount)
    )
}

private func faultAudit() throws -> AuditedFaultCampaign {
    let campaign = try StandardFaultCampaign.make()
    return try FaultAuditKernel.close(
        campaign: campaign,
        observations: StandardFaultCampaign.apparatusObservations(for: campaign)
    )
}
