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
    #expect(envelope.faultScenarioCount?.rawValue == 33)
    #expect(envelope.injectedFaultCount?.rawValue == 38)
    #expect(envelope.faultDigest == faults.digest)
    #expect(envelope.diagnostics.contains { $0.subject == "fault-behavior" })
}

@Test
func partialTargetFaultEvidenceBindsCampaignAndTargetWithoutAssuring() throws {
    let closed = try AuditKernel.close(try catalog(executionCount: 3))
    let campaign = try faultAudit()
    let target = try Digest.sha256(Data("target-result".utf8))
    let report = try AssuredReport(
        catalog: closed,
        faultEvidence: .partial(campaign, targetEvidence: target)
    )
    let encoded = try ReportCodec.encode(report)
    let envelope = try ReportCodec.decodeEnvelope(encoded)
    #expect(report.verdict == .gaps)
    #expect(envelope.faultStatus == .partial)
    #expect(envelope.faultCampaignDigest == campaign.digest)
    #expect(envelope.faultTargetEvidenceDigest == target)
    #expect(envelope.diagnostics.contains { $0.subject == "fault-coverage" })
    #expect(envelope.diagnostics.contains {
        $0.subject == "target-fault-response:process-launch"
            && $0.detail == "first-party boundary rejected the injected fault; target response unverified"
    })
    guard case .object(var fields) = try StrictJSON.decode(encoded),
        case .object(var faults)? = fields["faults"] else {
        Issue.record("partial fault report was not an object")
        return
    }
    faults["targetEvidenceDigest"] = .string(try Digest.sha256(Data("other".utf8)).rawValue)
    fields["faults"] = .object(faults)
    do {
        let decoded = try ReportCodec.decodeEnvelope(StrictJSON.encode(.object(fields)))
        Issue.record("unbound target evidence was accepted")
        #expect(decoded.faultTargetEvidenceDigest == nil)
    } catch let error {
        guard case .invalidFaultBinding = error else {
            Issue.record("wrong fault binding error: \(error)")
            return
        }
    }
}

@Test
func unverifiedFaultsCannotCarryAssuredVerdict() throws {
    let closed = try AuditKernel.close(try catalog(executionCount: 1))
    let report = try AssuredReport(catalog: closed, faultEvidence: .unverified)
    #expect(closed.verdict == .gaps)
    #expect(FaultVerdictDecision.decide(base: .assured, evidence: .unverified) == .gaps)
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
func wireCannotClaimVerifiedFaultsWithoutAReviewedCertificate() throws {
    let closed = try AuditKernel.close(try catalog(executionCount: 1))
    let report = try AssuredReport(catalog: closed, faultEvidence: .unverified)
    guard case .object(var fields) = try StrictJSON.decode(ReportCodec.encode(report)) else {
        Issue.record("report was not an object")
        return
    }
    fields["faults"] = .object([
        "status": .string("verified"),
        "digest": .string(try Digest.sha256(Data("forged".utf8)).rawValue),
        "injectedPoints": .number("1"),
        "scenarios": .number("2"),
    ])
    fields["verdict"] = .string("ASSURED")
    #expect(throws: ReportError.untrustedVerifiedFaultClaim) {
        try ReportCodec.decodeEnvelope(StrictJSON.encode(.object(fields)))
    }
    guard case .object(let schema) = ReportCodec.schema(),
        case .object(let properties)? = schema["properties"],
        case .object(let faults)? = properties["faults"],
        case .array(let alternatives)? = faults["oneOf"] else {
        Issue.record("fault schema was unavailable")
        return
    }
    #expect(alternatives.count == 3)
    #expect(!alternatives.contains { value in
        guard case .object(let item) = value,
            case .object(let itemProperties)? = item["properties"],
            case .object(let status)? = itemProperties["status"] else {
            return false
        }
        return status["const"] == .string("verified")
    })
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
func catalogDigestBindsBothClaimDefinitionNamesWithoutChangingClaimIDs() throws {
    let catalogs = [
        try catalog(executionCount: 1),
        try catalog(executionCount: 1, preservationName: "changed-preservation"),
        try catalog(executionCount: 1, detectionName: "changed-detection"),
    ]
    let envelopes = try catalogs.map { evidence in
        let report = try AssuredReport(
            catalog: AuditKernel.close(evidence),
            faultEvidence: .unverified
        )
        return try ReportCodec.decodeEnvelope(ReportCodec.encode(report))
    }
    #expect(Set(envelopes.map(\.catalogDigest)).count == 3)
    #expect(envelopes.allSatisfy { $0.verdict == .gaps })
}

@Test
func catalogDigestBindsExecutionVolumeDespiteUnchangedScoreAndVerdict() throws {
    let first = try AssuredReport(
        catalog: AuditKernel.close(try catalog(executionCount: 1)),
        faultEvidence: .unverified
    )
    let second = try AssuredReport(
        catalog: AuditKernel.close(try catalog(executionCount: 999)),
        faultEvidence: .unverified
    )
    #expect(first.verdict == second.verdict)
    #expect(first.score == second.score)
    let firstEnvelope = try ReportCodec.decodeEnvelope(ReportCodec.encode(first))
    let secondEnvelope = try ReportCodec.decodeEnvelope(ReportCodec.encode(second))
    #expect(firstEnvelope.catalogDigest != secondEnvelope.catalogDigest)
}

@Test
func unprovenIrrelevanceCannotIncreaseScore() throws {
    let evidence = try catalog(executionCount: 1, observation: .claimStatus(.provenIrrelevant))
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
func auditRejectsFailureReferencesOutsideDeclaredDomains() throws {
    let absentClaim = try ClaimID.parse("absent-claim")
    let absentWorld = try WorldID.parse("absent-world")
    let absentMutant = try MutantID.parse("absent-mutant")
    let knownClaim = try ClaimID.parse("preservation-1")
    let knownWorld = try WorldID.parse("world-1")
    let knownMutant = try MutantID.parse("mutant-1")
    #expect(throws: AuditError.unknownPreservationFailure(absentClaim, knownWorld)) {
        try AuditKernel.close(catalog(
            executionCount: 1,
            failures: [.clean(.preservationViolation(absentClaim, knownWorld))]
        ))
    }
    #expect(throws: AuditError.unknownBaselineWorld(absentWorld)) {
        try AuditKernel.close(catalog(
            executionCount: 1,
            failures: [.clean(.baselineCrashed(try TestID.parse("test-1"), absentWorld))]
        ))
    }
    #expect(throws: AuditError.unknownMutantFailure(absentMutant)) {
        try AuditKernel.close(catalog(
            executionCount: 1,
            failures: [.mutant(.notReached(absentMutant))]
        ))
    }
    #expect(throws: AuditError.unknownDetectionFailure(knownClaim)) {
        try AuditKernel.close(catalog(
            executionCount: 1,
            failures: [.mutant(.survived(knownMutant, knownClaim))]
        ))
    }
}

@Test
func catalogDigestDistinguishesEveryFailureKindAndDiagnosticField() throws {
    let preservation = try ClaimID.parse("preservation-1")
    let detection = try ClaimID.parse("detection-1")
    let world = try WorldID.parse("world-1")
    let mutant = try MutantID.parse("mutant-1")
    let test = try TestID.parse("test-1")
    let diagnostic = Diagnostic(code: .missingEvidence, subject: "apparatus", detail: "failed")
    let failures: [ExecutionFailure] = [
        .clean(.preservationViolation(preservation, world)),
        .clean(.baselineTestFailed(test, world)),
        .clean(.baselineCrashed(test, world)),
        .mutant(.survived(mutant, detection)),
        .mutant(.notReached(mutant)),
        .mutant(.notInfected(mutant)),
        .mutant(.compilerRejected(mutant)),
        .mutant(.equivalentWithoutProof(mutant)),
        .apparatus(.process(diagnostic)),
        .apparatus(.codec(diagnostic)),
        .apparatus(.store(diagnostic)),
        .apparatus(.toolchain(diagnostic)),
        .apparatus(.resourceOwnership(diagnostic)),
        .apparatus(.incompleteCatalog(diagnostic)),
        .apparatus(.process(Diagnostic(code: .lawViolated, subject: "apparatus", detail: "failed"))),
        .apparatus(.process(Diagnostic(code: .missingEvidence, subject: "other", detail: "failed"))),
        .apparatus(.process(Diagnostic(code: .missingEvidence, subject: "apparatus", detail: "other"))),
    ]
    var digests = Set<Digest>()
    for failure in failures {
        let report = try AssuredReport(
            catalog: AuditKernel.close(catalog(executionCount: 1, failures: [failure])),
            faultEvidence: .unverified
        )
        let envelope = try ReportCodec.decodeEnvelope(ReportCodec.encode(report))
        #expect(digests.insert(envelope.catalogDigest).inserted)
    }
    #expect(digests.count == failures.count)
}

@Test
func catalogDigestBindsEveryFailurePayloadIndependently() throws {
    let preservationOne = try ClaimID.parse("preservation-1")
    let preservationTwo = try ClaimID.parse("preservation-2")
    let detectionOne = try ClaimID.parse("detection-1")
    let detectionTwo = try ClaimID.parse("detection-2")
    let worldOne = try WorldID.parse("world-1")
    let worldTwo = try WorldID.parse("world-2")
    let mutantOne = try MutantID.parse("mutant-1")
    let mutantTwo = try MutantID.parse("mutant-2")
    let testOne = try TestID.parse("test-1")
    let testTwo = try TestID.parse("test-2")
    let pairs: [(ExecutionFailure, ExecutionFailure)] = [
        (.clean(.preservationViolation(preservationOne, worldOne)),
         .clean(.preservationViolation(preservationTwo, worldOne))),
        (.clean(.preservationViolation(preservationOne, worldOne)),
         .clean(.preservationViolation(preservationOne, worldTwo))),
        (.clean(.baselineTestFailed(testOne, worldOne)),
         .clean(.baselineTestFailed(testTwo, worldOne))),
        (.clean(.baselineTestFailed(testOne, worldOne)),
         .clean(.baselineTestFailed(testOne, worldTwo))),
        (.clean(.baselineCrashed(testOne, worldOne)),
         .clean(.baselineCrashed(testTwo, worldOne))),
        (.clean(.baselineCrashed(testOne, worldOne)),
         .clean(.baselineCrashed(testOne, worldTwo))),
        (.mutant(.survived(mutantOne, detectionOne)),
         .mutant(.survived(mutantTwo, detectionOne))),
        (.mutant(.survived(mutantOne, detectionOne)),
         .mutant(.survived(mutantOne, detectionTwo))),
        (.mutant(.notReached(mutantOne)), .mutant(.notReached(mutantTwo))),
        (.mutant(.notInfected(mutantOne)), .mutant(.notInfected(mutantTwo))),
        (.mutant(.compilerRejected(mutantOne)), .mutant(.compilerRejected(mutantTwo))),
        (.mutant(.equivalentWithoutProof(mutantOne)), .mutant(.equivalentWithoutProof(mutantTwo))),
    ]
    for (first, second) in pairs {
        let firstReport = try AssuredReport(
            catalog: AuditKernel.close(try pairedDomainCatalog(failure: first)),
            faultEvidence: .unverified
        )
        let secondReport = try AssuredReport(
            catalog: AuditKernel.close(try pairedDomainCatalog(failure: second)),
            faultEvidence: .unverified
        )
        let firstDigest = try ReportCodec.decodeEnvelope(ReportCodec.encode(firstReport)).catalogDigest
        let secondDigest = try ReportCodec.decodeEnvelope(ReportCodec.encode(secondReport)).catalogDigest
        #expect(firstDigest != secondDigest)
    }
}

@Test
func catalogDigestBindsMutationWorldEvenWhenOtherObservationFieldsMatch() throws {
    let mutant = try MutantID.parse("mutant-1")
    let failure = ExecutionFailure.mutant(.notReached(mutant))
    let declared = try AssuredReport(
        catalog: AuditKernel.close(pairedDomainCatalog(failure: failure, mutationWorldOrder: .declared)),
        faultEvidence: .unverified
    )
    let reversed = try AssuredReport(
        catalog: AuditKernel.close(pairedDomainCatalog(failure: failure, mutationWorldOrder: .reversed)),
        faultEvidence: .unverified
    )
    let first = try ReportCodec.decodeEnvelope(ReportCodec.encode(declared))
    let second = try ReportCodec.decodeEnvelope(ReportCodec.encode(reversed))
    #expect(first.catalogDigest != second.catalogDigest)
    #expect(first.verdict == second.verdict)
    #expect(first.scorePassed == second.scorePassed)
    #expect(first.scoreTotal == second.scoreTotal)
}

@Test
func catalogDigestBindsContinuityThatChangesVerdict() throws {
    let eventFree = try AssuredReport(
        catalog: AuditKernel.close(try catalog(executionCount: 1, inputContinuity: .eventFree)),
        faultEvidence: .unverified
    )
    let ambiguous = try AssuredReport(
        catalog: AuditKernel.close(try catalog(executionCount: 1, inputContinuity: .attributeAmbiguous)),
        faultEvidence: .unverified
    )
    let eventFreeEnvelope = try ReportCodec.decodeEnvelope(ReportCodec.encode(eventFree))
    let ambiguousEnvelope = try ReportCodec.decodeEnvelope(ReportCodec.encode(ambiguous))
    #expect(eventFreeEnvelope.catalogDigest != ambiguousEnvelope.catalogDigest)
    #expect(eventFreeEnvelope.verdict == .gaps)
    #expect(ambiguousEnvelope.verdict == .gapsAndUnsettled)
}

@Test
func catalogDigestBindsIndependentReviewEvidence() throws {
    let accepted = try AssuredReport(
        catalog: AuditKernel.close(try catalog(executionCount: 1, reviewEvidence: .present)),
        faultEvidence: .unverified
    )
    let missing = try AssuredReport(
        catalog: AuditKernel.close(try catalog(executionCount: 1, reviewEvidence: .absent)),
        faultEvidence: .unverified
    )
    let acceptedEnvelope = try ReportCodec.decodeEnvelope(ReportCodec.encode(accepted))
    let missingEnvelope = try ReportCodec.decodeEnvelope(ReportCodec.encode(missing))
    #expect(acceptedEnvelope.catalogDigest != missingEnvelope.catalogDigest)
    #expect(acceptedEnvelope.verdict == .gaps)
    #expect(missingEnvelope.verdict == .gapsAndUnsettled)
}

@Test
func catalogDigestBindsNestedLawDiagnostic() throws {
    let variants: [Diagnostic?] = [
        nil,
        Diagnostic(code: .missingEvidence, subject: "law-observation", detail: "independent diagnostic"),
        Diagnostic(code: .lawViolated, subject: "law-observation", detail: "independent diagnostic"),
        Diagnostic(code: .missingEvidence, subject: "other-observation", detail: "independent diagnostic"),
        Diagnostic(code: .missingEvidence, subject: "law-observation", detail: "different diagnostic"),
    ]
    var digests = Set<Digest>()
    for diagnostic in variants {
        let report = try AssuredReport(
            catalog: AuditKernel.close(try catalog(executionCount: 1, observation: .lawDiagnostic(diagnostic))),
            faultEvidence: .unverified
        )
        let envelope = try ReportCodec.decodeEnvelope(ReportCodec.encode(report))
        #expect(digests.insert(envelope.catalogDigest).inserted)
    }
}

@Test
func catalogDigestBindsEveryNestedObservationKind() throws {
    let variants: [ObservationFixture] = [
        .baseline,
        .claimStatus(.failed),
        .claimDiagnostic(Diagnostic(code: .lawViolated, subject: "claim", detail: "changed")),
        .mutationReached(.failed),
        .mutationInfected(.failed),
        .mutationDetected(.failed),
        .lawStatus(.failed),
        .schemaStatus(.failed),
    ]
    var digests = Set<Digest>()
    for variant in variants {
        let report = try AssuredReport(
            catalog: AuditKernel.close(try catalog(executionCount: 1, observation: variant)),
            faultEvidence: .unverified
        )
        let envelope = try ReportCodec.decodeEnvelope(ReportCodec.encode(report))
        #expect(digests.insert(envelope.catalogDigest).inserted)
    }
}

@Test
func catalogDigestBindsEveryModeledWorldAxis() throws {
    let variants: [WorldDefinition] = [
        try modeledWorld(),
        try modeledWorld(build: .release),
        try modeledWorld(operatingSystem: .iOS, deviceFamily: .phone),
        try modeledWorld(deviceID: "device-2"),
        try modeledWorld(locale: .japaneseJapan),
        try modeledWorld(layoutDirection: .rightToLeft),
        try modeledWorld(appearance: .dark),
        try modeledWorld(accessibility: .voiceOver),
        try modeledWorld(permissionKind: .microphone),
        try modeledWorld(permissionState: .denied),
        try modeledWorld(location: .moving),
        try modeledWorld(biometrics: .enrolled),
        try modeledWorld(lifecycle: .background),
        try modeledWorld(data: .malformed),
        try modeledWorld(serviceFault: .timeout),
        try modeledWorld(cancellation: .duringOperation),
        try modeledWorld(scheduleID: "schedule-2"),
        try modeledWorld(scheduleDecisions: [1]),
    ]
    var digests = Set<Digest>()
    for definition in variants {
        let report = try AssuredReport(
            catalog: AuditKernel.close(try catalog(
                executionCount: 1,
                declaredWorlds: .from([.modeled(definition)])
            )),
            faultEvidence: .unverified
        )
        let envelope = try ReportCodec.decodeEnvelope(ReportCodec.encode(report))
        #expect(digests.insert(envelope.catalogDigest).inserted)
    }
    #expect(digests.count == variants.count)
    let unmodeled = try AssuredReport(
        catalog: AuditKernel.close(try catalog(executionCount: 1)),
        faultEvidence: .unverified
    )
    let unmodeledEnvelope = try ReportCodec.decodeEnvelope(ReportCodec.encode(unmodeled))
    #expect(digests.insert(unmodeledEnvelope.catalogDigest).inserted)
}

@Test
func auditRejectsConflictingOrImpossibleWorldDefinitions() throws {
    let first = try modeledWorld()
    let second = try modeledWorld(appearance: .dark)
    let id = first.id
    #expect(throws: AuditError.conflictingWorldDefinition(id)) {
        try AuditKernel.close(catalog(
            executionCount: 1,
            declaredWorlds: .from([.modeled(first), .modeled(second)])
        ))
    }
    #expect(throws: AuditError.conflictingWorldDefinition(id)) {
        try AuditKernel.close(catalog(
            executionCount: 1,
            declaredWorlds: .from([.unmodeledHost(id), .modeled(first)])
        ))
    }
    #expect(throws: AuditError.duplicateWorld(id)) {
        try AuditKernel.close(catalog(
            executionCount: 1,
            declaredWorlds: .from([.modeled(first), .modeled(first)])
        ))
    }
    #expect(throws: AuditError.impossibleWorldDefinition(id)) {
        try AuditKernel.close(catalog(
            executionCount: 1,
            declaredWorlds: .from([.modeled(try modeledWorld(deviceFamily: .phone))])
        ))
    }
    #expect(throws: AuditError.impossibleWorldDefinition(id)) {
        try AuditKernel.close(catalog(
            executionCount: 1,
            declaredWorlds: .from([.modeled(try modeledWorld(scheduleDecisions: [-1]))])
        ))
    }
    let unmodeled = try catalog(executionCount: 1)
    #expect(unmodeled.coverageGaps.contains { $0.subject == id.rawValue })
    let clean = try modeledWorld(mutant: .clean)
    let mutant = try modeledWorld(mutant: .mutant(MutantID.parse("mutant-1")))
    #expect(clean == mutant)
}

@Test
func swiftVerdictOracleIsExhaustiveAndStable() {
    let lines = VerdictOracle.text().split(separator: "\n")
    #expect(lines.count == 24)
    #expect(lines.first == "absent\tabsent\tabsent\tcomplete\tASSURED")
    #expect(lines.last == "present\tpresent\tpresent\tscoped\tINVALID")
    let reportLines = ReportVerdictOracle.text().split(separator: "\n")
    #expect(reportLines.count == 28)
    #expect(reportLines.first == "report\tASSURED\tverified\tASSURED")
    #expect(reportLines.last == "report\tINVALID\tunverified\tINVALID")
}

private enum ReviewEvidenceFixture {
    case present
    case absent
}

private enum MutationWorldOrder {
    case declared
    case reversed
}

private func pairedDomainCatalog(
    failure: ExecutionFailure,
    mutationWorldOrder: MutationWorldOrder = .declared
) throws -> EvidenceCatalog {
    let base = try catalog(executionCount: 1)
    let preservation = [try ClaimID.parse("preservation-1"), try ClaimID.parse("preservation-2")]
    let detection = [try ClaimID.parse("detection-1"), try ClaimID.parse("detection-2")]
    let declaredPreservation = DeclaredClaims<Preservation>.from(try preservation.map {
        try Claim<Preservation>.preservation(id: $0, name: $0.rawValue)
    })
    let declaredDetection = DeclaredClaims<Detection>.from(try detection.map {
        try Claim<Detection>.detection(id: $0, name: $0.rawValue)
    })
    let worlds = [try WorldID.parse("world-1"), try WorldID.parse("world-2")]
    let mutants = [try MutantID.parse("mutant-1"), try MutantID.parse("mutant-2")]
    let observations = (preservation + detection).flatMap { claim in
        worlds.map { world in
            ClaimObservation(claim: claim, world: world, status: .passed, diagnostic: nil)
        }
    }
    let mutationWorlds: [WorldID]
    switch mutationWorldOrder {
    case .declared:
        mutationWorlds = worlds
    case .reversed:
        mutationWorlds = Array(worlds.reversed())
    }
    return EvidenceCatalog(
        run: base.run,
        scope: base.scope,
        inputContinuity: base.inputContinuity,
        runtimePipeline: base.runtimePipeline,
        preservationClaims: declaredPreservation,
        detectionClaims: declaredDetection,
        worlds: .unmodeledHosts(worlds),
        mutants: mutants,
        claimObservations: observations,
        mutationObservations: mutants.flatMap { mutant in
            mutationWorlds.map { world in
                MutationObservation(mutant: mutant, world: world, reached: .passed, infected: .passed, detected: .passed)
            }
        },
        lawObservations: base.lawObservations,
        schemaObservations: base.schemaObservations,
        failures: [failure],
        review: base.review,
        executionCount: base.executionCount
    )
}

private enum ObservationFixture {
    case baseline
    case claimStatus(ObservationStatus)
    case claimDiagnostic(Diagnostic)
    case mutationReached(ObservationStatus)
    case mutationInfected(ObservationStatus)
    case mutationDetected(ObservationStatus)
    case lawStatus(ObservationStatus)
    case lawDiagnostic(Diagnostic?)
    case schemaStatus(ObservationStatus)
}

private func catalog(
    executionCount: Int,
    failures: [ExecutionFailure] = [],
    inputContinuity: FileEventContinuity = .eventFree,
    reviewEvidence: ReviewEvidenceFixture = .present,
    observation: ObservationFixture = .baseline,
    preservationName: String = "preservation",
    detectionName: String = "detection",
    declaredWorlds: DeclaredWorlds? = nil
) throws -> EvidenceCatalog {
    let preservation = try ClaimID.parse("preservation-1")
    let detection = try ClaimID.parse("detection-1")
    let world = try WorldID.parse("world-1")
    let mutant = try MutantID.parse("mutant-1")
    var claimStatus: ObservationStatus = .passed
    var claimDiagnostic: Diagnostic? = nil
    var mutationReached: ObservationStatus = .passed
    var mutationInfected: ObservationStatus = .passed
    var mutationDetected: ObservationStatus = .passed
    var lawStatus: ObservationStatus = .passed
    var lawDiagnostic: Diagnostic? = nil
    var schemaStatus: ObservationStatus = .passed
    switch observation {
    case .baseline:
        break
    case .claimStatus(let status):
        claimStatus = status
    case .claimDiagnostic(let diagnostic):
        claimDiagnostic = diagnostic
    case .mutationReached(let status):
        mutationReached = status
    case .mutationInfected(let status):
        mutationInfected = status
    case .mutationDetected(let status):
        mutationDetected = status
    case .lawStatus(let status):
        lawStatus = status
    case .lawDiagnostic(let diagnostic):
        lawDiagnostic = diagnostic
    case .schemaStatus(let status):
        schemaStatus = status
    }
    let laws = LawCode.allCases.map {
        LawObservation(code: $0, status: lawStatus, diagnostic: lawDiagnostic)
    }
    let reviewDigest: Digest?
    switch reviewEvidence {
    case .present:
        reviewDigest = try Digest.sha256(Data("review".utf8))
    case .absent:
        reviewDigest = nil
    }
    let worlds: DeclaredWorlds
    switch declaredWorlds {
    case .some(let definitions):
        worlds = definitions
    case .none:
        worlds = .unmodeledHosts([world])
    }
    return EvidenceCatalog(
        run: try RunID.parse("run-report"),
        scope: .complete,
        inputContinuity: inputContinuity,
        runtimePipeline: .unverified,
        preservationClaims: .from([try Claim<Preservation>.preservation(
            id: preservation,
            name: preservationName
        )]),
        detectionClaims: .from([try Claim<Detection>.detection(
            id: detection,
            name: detectionName
        )]),
        worlds: worlds,
        mutants: [mutant],
        claimObservations: [
            ClaimObservation(claim: preservation, world: world, status: claimStatus, diagnostic: claimDiagnostic),
            ClaimObservation(claim: detection, world: world, status: .passed, diagnostic: nil),
        ],
        mutationObservations: [MutationObservation(
            mutant: mutant,
            world: world,
            reached: mutationReached,
            infected: mutationInfected,
            detected: mutationDetected
        )],
        lawObservations: laws,
        schemaObservations: [SchemaObservation(version: .v2, status: schemaStatus)],
        failures: failures,
        review: IndependentReview(
            status: .accepted,
            evidence: reviewDigest
        ),
        executionCount: try EvidenceCount.nonnegative(executionCount)
    )
}

private func modeledWorld(
    build: BuildConfiguration = .debug,
    operatingSystem: AppleOperatingSystem = .macOS,
    deviceID: String = "device-1",
    deviceFamily: DeviceFamily = .mac,
    locale: LocaleScenario = .englishUnitedStates,
    layoutDirection: LayoutDirection = .leftToRight,
    appearance: Appearance = .light,
    accessibility: AccessibilityScenario = .standard,
    permissionKind: PermissionKind = .camera,
    permissionState: PermissionState = .granted,
    location: LocationScenario = .fixed,
    biometrics: BiometricScenario = .succeeds,
    lifecycle: LifecycleScenario = .foreground,
    data: DataScenario = .typical,
    serviceFault: ServiceFault = .none,
    cancellation: CancellationScenario = .never,
    scheduleID: String = "schedule-1",
    scheduleDecisions: [Int] = [],
    mutant: MutantSelection = .clean
) throws -> WorldDefinition {
    WorldDefinition(world: World(
        id: try WorldID.parse("world-1"),
        build: build,
        operatingSystem: operatingSystem,
        device: DeviceProfile(id: try DeviceID.parse(deviceID), family: deviceFamily),
        locale: locale,
        layoutDirection: layoutDirection,
        appearance: appearance,
        accessibility: accessibility,
        permission: PermissionScenario(kind: permissionKind, state: permissionState),
        location: location,
        biometrics: biometrics,
        lifecycle: lifecycle,
        data: data,
        serviceFault: serviceFault,
        cancellation: cancellation,
        schedule: ScheduleScenario(id: try ScheduleID.parse(scheduleID), decisions: scheduleDecisions),
        mutant: mutant
    ))
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
