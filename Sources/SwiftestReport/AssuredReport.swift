import Foundation
import SwiftestCodec
import SwiftestDecision
import SwiftestFaults
import SwiftestModel
import SwiftestScore

public enum ReportError: Error, Equatable, Sendable {
    case score(NumericValueError)
    case codec(StrictJSONError)
    case digest(DigestError)
    case identifier(IdentifierError)
    case schema(NumericValueError)
    case unsupportedSchema(SchemaVersion)
    case invalidVerdict(String)
    case invalidScope(String)
    case invalidFaultStatus(String)
    case untrustedVerifiedFaultClaim
    case invalidDiagnostic(String)
    case invalidScore(EvidenceCount, EvidenceCount)
    case invalidFaultSummary(EvidenceCount?, EvidenceCount?)
    case invalidFaultBinding(expected: Digest, actual: Digest)
    case decisionMismatch(expected: Verdict, actual: Verdict)
}

public enum FaultEvidence: Sendable {
    case unverified
    case structural(AuditedFaultCampaign)
    case partial(AuditedFaultCampaign, targetEvidence: Digest)
}

public enum FaultEvidenceStatus: String, CaseIterable, Sendable {
    case verified
    case structural
    case partial
    case unverified
}

public enum FaultVerdictDecision {
    public static func decide(base: Verdict, evidence: FaultEvidenceStatus) -> Verdict {
        switch evidence {
        case .verified:
            base
        case .structural, .partial, .unverified:
            switch base {
            case .assured, .changeAssured, .scopeAssured, .gaps:
                .gaps
            case .unsettled, .gapsAndUnsettled:
                .gapsAndUnsettled
            case .invalid:
                .invalid
            }
        }
    }
}

public enum ReportVerdictOracle {
    public static func text() -> String {
        let lines = Verdict.allCases.flatMap { base in
            FaultEvidenceStatus.allCases.map { evidence in
                [
                    "report",
                    base.rawValue,
                    evidence.rawValue,
                    FaultVerdictDecision.decide(base: base, evidence: evidence).rawValue,
                ].joined(separator: "\t")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

public struct AssuredReport: Sendable {
    public let catalog: AuditedCatalog<Closed>
    public let faults: FaultEvidence
    public let score: AssuranceScore

    public var verdict: Verdict {
        switch faults {
        case .structural:
            FaultVerdictDecision.decide(base: catalog.verdict, evidence: .structural)
        case .partial:
            FaultVerdictDecision.decide(base: catalog.verdict, evidence: .partial)
        case .unverified:
            FaultVerdictDecision.decide(base: catalog.verdict, evidence: .unverified)
        }
    }

    public var diagnostics: [Diagnostic] {
        switch faults {
        case .structural:
            catalog.diagnostics + [Diagnostic(
                code: .missingEvidence,
                subject: "fault-behavior",
                detail: "full target fault coverage and independent behavior not established"
            )]
        case .partial(let audit, _):
            catalog.diagnostics + audit.pointIDs.map { point in
                Diagnostic(
                    code: .missingEvidence,
                    subject: "target-fault-response:" + point.rawValue,
                    detail: "first-party boundary rejected the injected fault; target response unverified"
                )
            } + [Diagnostic(
                code: .missingEvidence,
                subject: "fault-coverage",
                detail: "full target campaign and independent review remain unverified"
            )]
        case .unverified:
            catalog.diagnostics + [Diagnostic(
                code: .missingEvidence,
                subject: "faults",
                detail: "target fault injection not executed"
            )]
        }
    }

    public init(
        catalog: AuditedCatalog<Closed>,
        faults: AuditedFaultCampaign
    ) throws(ReportError) {
        try self.init(catalog: catalog, faultEvidence: .structural(faults))
    }

    public init(
        catalog: AuditedCatalog<Closed>,
        faultEvidence: FaultEvidence
    ) throws(ReportError) {
        self.catalog = catalog
        self.faults = faultEvidence
        do {
            self.score = try AssuranceScore.measure(catalog.evidence)
        } catch let error {
            throw .score(error)
        }
    }
}

public struct ReportEnvelope: Equatable, Sendable {
    public let schema: SchemaVersion
    public let run: RunID
    public let scope: ScopeKind
    public let verdict: Verdict
    public let scorePassed: EvidenceCount
    public let scoreTotal: EvidenceCount
    public let executionCount: EvidenceCount
    public let catalogDigest: Digest
    public let diagnostics: [Diagnostic]
    public let faultStatus: FaultEvidenceStatus
    public let faultDigest: Digest?
    public let faultScenarioCount: EvidenceCount?
    public let injectedFaultCount: EvidenceCount?
    public let faultCampaignDigest: Digest?
    public let faultTargetEvidenceDigest: Digest?

    public init(
        schema: SchemaVersion,
        run: RunID,
        scope: ScopeKind,
        verdict: Verdict,
        scorePassed: EvidenceCount,
        scoreTotal: EvidenceCount,
        executionCount: EvidenceCount,
        catalogDigest: Digest,
        diagnostics: [Diagnostic],
        faultStatus: FaultEvidenceStatus,
        faultDigest: Digest?,
        faultScenarioCount: EvidenceCount?,
        injectedFaultCount: EvidenceCount?,
        faultCampaignDigest: Digest? = nil,
        faultTargetEvidenceDigest: Digest? = nil
    ) {
        self.schema = schema
        self.run = run
        self.scope = scope
        self.verdict = verdict
        self.scorePassed = scorePassed
        self.scoreTotal = scoreTotal
        self.executionCount = executionCount
        self.catalogDigest = catalogDigest
        self.diagnostics = diagnostics
        self.faultStatus = faultStatus
        self.faultDigest = faultDigest
        self.faultScenarioCount = faultScenarioCount
        self.injectedFaultCount = injectedFaultCount
        self.faultCampaignDigest = faultCampaignDigest
        self.faultTargetEvidenceDigest = faultTargetEvidenceDigest
    }
}

public enum ReportCodec {
    public static func encode(_ report: AssuredReport) throws(ReportError) -> Data {
        let digest: Digest
        do {
            digest = try StrictJSON.canonicalDigest(catalogValue(report.catalog.evidence))
        } catch let error {
            throw .digest(error)
        }
        let faultValue: JSONValue
        switch report.faults {
        case .unverified:
            faultValue = .object(["status": .string(FaultEvidenceStatus.unverified.rawValue)])
        case .structural(let audit):
            faultValue = .object([
                "status": .string(FaultEvidenceStatus.structural.rawValue),
                "digest": .string(audit.digest.rawValue),
                "injectedPoints": .number(String(audit.injectedPointCount.rawValue)),
                "scenarios": .number(String(audit.scenarioCount.rawValue)),
            ])
        case .partial(let audit, let targetEvidence):
            let bound = try partialFaultDigest(campaign: audit.digest, target: targetEvidence)
            faultValue = .object([
                "status": .string(FaultEvidenceStatus.partial.rawValue),
                "digest": .string(bound.rawValue),
                "campaignDigest": .string(audit.digest.rawValue),
                "targetEvidenceDigest": .string(targetEvidence.rawValue),
                "injectedPoints": .number(String(audit.injectedPointCount.rawValue)),
                "scenarios": .number(String(audit.scenarioCount.rawValue)),
            ])
        }
        let value = JSONValue.object([
            "catalogDigest": .string(digest.rawValue),
            "diagnostics": .array(report.diagnostics.map(diagnosticValue)),
            "executionCount": .number(String(report.catalog.evidence.executionCount.rawValue)),
            "faults": faultValue,
            "run": .string(report.catalog.evidence.run.rawValue),
            "schema": .number(String(SchemaVersion.v2.rawValue)),
            "scope": .string(report.catalog.evidence.scope.rawValue),
            "score": .object([
                "passed": .number(String(report.score.passed.rawValue)),
                "total": .number(String(report.score.total.rawValue)),
            ]),
            "verdict": .string(report.verdict.rawValue),
        ])
        return StrictJSON.encode(value)
    }

    public static func decodeEnvelope(_ data: Data) throws(ReportError) -> ReportEnvelope {
        let value: JSONValue
        do {
            value = try StrictJSON.decode(data)
        } catch let error {
            throw .codec(error)
        }
        var reader: JSONObjectReader
        do {
            reader = try JSONObjectReader(value)
        } catch let error {
            throw .codec(error)
        }
        let schemaRaw: Int
        let runRaw: String
        let scopeRaw: String
        let verdictRaw: String
        let executionCountRaw: Int
        let digestRaw: String
        let diagnosticsValue: JSONValue
        let faultValue: JSONValue
        let scoreValue: JSONValue
        do {
            schemaRaw = try reader.requiredInteger("schema")
            runRaw = try reader.requiredString("run")
            scopeRaw = try reader.requiredString("scope")
            verdictRaw = try reader.requiredString("verdict")
            executionCountRaw = try reader.requiredInteger("executionCount")
            digestRaw = try reader.requiredString("catalogDigest")
            diagnosticsValue = try reader.requiredValue("diagnostics")
            faultValue = try reader.requiredValue("faults")
            scoreValue = try reader.requiredValue("score")
            try reader.finish()
        } catch let error {
            throw .codec(error)
        }
        guard case .array(let diagnosticValues) = diagnosticsValue else {
            throw .codec(.expectedArray("diagnostics"))
        }
        var diagnostics: [Diagnostic] = []
        for value in diagnosticValues {
            let codeRaw: String
            let subject: String
            let detail: String
            do {
                var diagnosticReader = try JSONObjectReader(value)
                codeRaw = try diagnosticReader.requiredString("code")
                subject = try diagnosticReader.requiredString("subject")
                detail = try diagnosticReader.requiredString("detail")
                try diagnosticReader.finish()
            } catch let error {
                throw .codec(error)
            }
            guard let code = DiagnosticCode(rawValue: codeRaw) else {
                throw .invalidDiagnostic(codeRaw)
            }
            diagnostics.append(Diagnostic(code: code, subject: subject, detail: detail))
        }
        var scoreReader: JSONObjectReader
        do {
            scoreReader = try JSONObjectReader(scoreValue)
        } catch let error {
            throw .codec(error)
        }
        var faultReader: JSONObjectReader
        do {
            faultReader = try JSONObjectReader(faultValue)
        } catch let error {
            throw .codec(error)
        }
        let faultStatusRaw: String
        do {
            faultStatusRaw = try faultReader.requiredString("status")
        } catch let error {
            throw .codec(error)
        }
        guard let faultStatus = FaultEvidenceStatus(rawValue: faultStatusRaw) else {
            throw .invalidFaultStatus(faultStatusRaw)
        }
        let faultDigestRaw: String?
        let faultScenarioCountRaw: Int?
        let injectedFaultCountRaw: Int?
        let campaignDigestRaw: String?
        let targetEvidenceDigestRaw: String?
        switch faultStatus {
        case .unverified:
            faultDigestRaw = nil
            faultScenarioCountRaw = nil
            injectedFaultCountRaw = nil
            campaignDigestRaw = nil
            targetEvidenceDigestRaw = nil
        case .structural:
            do {
                faultDigestRaw = try faultReader.requiredString("digest")
                injectedFaultCountRaw = try faultReader.requiredInteger("injectedPoints")
                faultScenarioCountRaw = try faultReader.requiredInteger("scenarios")
            } catch let error {
                throw .codec(error)
            }
            campaignDigestRaw = nil
            targetEvidenceDigestRaw = nil
        case .verified:
            throw .untrustedVerifiedFaultClaim
        case .partial:
            do {
                faultDigestRaw = try faultReader.requiredString("digest")
                campaignDigestRaw = try faultReader.requiredString("campaignDigest")
                targetEvidenceDigestRaw = try faultReader.requiredString("targetEvidenceDigest")
                injectedFaultCountRaw = try faultReader.requiredInteger("injectedPoints")
                faultScenarioCountRaw = try faultReader.requiredInteger("scenarios")
            } catch let error {
                throw .codec(error)
            }
        }
        do {
            try faultReader.finish()
        } catch let error {
            throw .codec(error)
        }
        let passedRaw: Int
        let totalRaw: Int
        do {
            passedRaw = try scoreReader.requiredInteger("passed")
            totalRaw = try scoreReader.requiredInteger("total")
            try scoreReader.finish()
        } catch let error {
            throw .codec(error)
        }
        let schema: SchemaVersion
        do {
            schema = try .parse(schemaRaw)
        } catch let error {
            throw .schema(error)
        }
        if schema != .v2 {
            throw .unsupportedSchema(schema)
        }
        let run: RunID
        do {
            run = try .parse(runRaw)
        } catch let error {
            throw .identifier(error)
        }
        guard let scope = ScopeKind(rawValue: scopeRaw) else {
            throw .invalidScope(scopeRaw)
        }
        guard let verdict = Verdict(rawValue: verdictRaw) else {
            throw .invalidVerdict(verdictRaw)
        }
        if faultStatus != .verified {
            switch verdict {
            case .assured, .changeAssured, .scopeAssured, .unsettled:
                throw .decisionMismatch(expected: .gapsAndUnsettled, actual: verdict)
            case .gaps, .gapsAndUnsettled, .invalid:
                break
            }
        }
        let passed: EvidenceCount
        let total: EvidenceCount
        let executionCount: EvidenceCount
        let faultScenarioCount: EvidenceCount?
        let injectedFaultCount: EvidenceCount?
        do {
            passed = try .nonnegative(passedRaw)
            total = try .nonnegative(totalRaw)
            executionCount = try .nonnegative(executionCountRaw)
            if let faultScenarioCountRaw, let injectedFaultCountRaw {
                faultScenarioCount = try .nonnegative(faultScenarioCountRaw)
                injectedFaultCount = try .nonnegative(injectedFaultCountRaw)
            } else {
                faultScenarioCount = nil
                injectedFaultCount = nil
            }
        } catch let error {
            throw .score(error)
        }
        if passed > total {
            throw .invalidScore(passed, total)
        }
        if faultStatus != .unverified {
            guard let scenarios = faultScenarioCount, let injected = injectedFaultCount,
                scenarios > .zero, injected > .zero else {
                throw .invalidFaultSummary(faultScenarioCount, injectedFaultCount)
            }
        }
        let digest: Digest
        let faultDigest: Digest?
        let campaignDigest: Digest?
        let targetEvidenceDigest: Digest?
        do {
            digest = try .parse(digestRaw)
            if let faultDigestRaw {
                faultDigest = try .parse(faultDigestRaw)
            } else {
                faultDigest = nil
            }
            if let campaignDigestRaw {
                campaignDigest = try .parse(campaignDigestRaw)
            } else {
                campaignDigest = nil
            }
            if let targetEvidenceDigestRaw {
                targetEvidenceDigest = try .parse(targetEvidenceDigestRaw)
            } else {
                targetEvidenceDigest = nil
            }
        } catch let error {
            throw .digest(error)
        }
        if let campaignDigest, let targetEvidenceDigest, let faultDigest {
            let expected = try partialFaultDigest(campaign: campaignDigest, target: targetEvidenceDigest)
            if expected != faultDigest {
                throw .invalidFaultBinding(expected: expected, actual: faultDigest)
            }
        }
        return ReportEnvelope(
            schema: schema,
            run: run,
            scope: scope,
            verdict: verdict,
            scorePassed: passed,
            scoreTotal: total,
            executionCount: executionCount,
            catalogDigest: digest,
            diagnostics: diagnostics,
            faultStatus: faultStatus,
            faultDigest: faultDigest,
            faultScenarioCount: faultScenarioCount,
            injectedFaultCount: injectedFaultCount,
            faultCampaignDigest: campaignDigest,
            faultTargetEvidenceDigest: targetEvidenceDigest
        )
    }

    private static func partialFaultDigest(campaign: Digest, target: Digest) throws(ReportError) -> Digest {
        let value = JSONValue.array([
            .string("swiftest-partial-fault-v1"),
            .string(campaign.rawValue),
            .string(target.rawValue),
        ])
        do {
            return try StrictJSON.canonicalDigest(value)
        } catch let error {
            throw .digest(error)
        }
    }

    public static func schema() -> JSONValue {
        .object([
            "$schema": .string("https://json-schema.org/draft/2020-12/schema"),
            "additionalProperties": .boolean(false),
            "properties": .object([
                "catalogDigest": .object(["pattern": .string("^[0-9a-f]{64}$"), "type": .string("string")]),
                "diagnostics": .object([
                    "items": .object([
                        "additionalProperties": .boolean(false),
                        "properties": .object([
                            "code": .object(["enum": .array(DiagnosticCode.allCases.map { .string($0.rawValue) })]),
                            "subject": .object(["type": .string("string")]),
                            "detail": .object(["type": .string("string")]),
                        ]),
                        "required": .array([.string("code"), .string("subject"), .string("detail")]),
                        "type": .string("object"),
                    ]),
                    "type": .string("array"),
                ]),
                "executionCount": .object(["minimum": .number("0"), "type": .string("integer")]),
                "faults": .object([
                    "oneOf": .array([
                        .object([
                            "additionalProperties": .boolean(false),
                            "properties": .object([
                                "status": .object(["const": .string("unverified")]),
                            ]),
                            "required": .array([.string("status")]),
                            "type": .string("object"),
                        ]),
                        .object([
                            "additionalProperties": .boolean(false),
                            "properties": .object([
                                "status": .object(["const": .string("structural")]),
                                "digest": .object(["pattern": .string("^[0-9a-f]{64}$"), "type": .string("string")]),
                                "injectedPoints": .object(["minimum": .number("1"), "type": .string("integer")]),
                                "scenarios": .object(["minimum": .number("1"), "type": .string("integer")]),
                            ]),
                            "required": .array([
                                .string("status"), .string("digest"), .string("injectedPoints"), .string("scenarios"),
                            ]),
                            "type": .string("object"),
                        ]),
                        .object([
                            "additionalProperties": .boolean(false),
                            "properties": .object([
                                "status": .object(["const": .string("partial")]),
                                "digest": .object(["pattern": .string("^[0-9a-f]{64}$"), "type": .string("string")]),
                                "campaignDigest": .object(["pattern": .string("^[0-9a-f]{64}$"), "type": .string("string")]),
                                "targetEvidenceDigest": .object(["pattern": .string("^[0-9a-f]{64}$"), "type": .string("string")]),
                                "injectedPoints": .object(["minimum": .number("1"), "type": .string("integer")]),
                                "scenarios": .object(["minimum": .number("1"), "type": .string("integer")]),
                            ]),
                            "required": .array([
                                .string("status"), .string("digest"), .string("campaignDigest"),
                                .string("targetEvidenceDigest"), .string("injectedPoints"), .string("scenarios"),
                            ]),
                            "type": .string("object"),
                        ]),
                    ]),
                ]),
                "run": .object(["minLength": .number("1"), "type": .string("string")]),
                "schema": .object(["const": .number("2")]),
                "scope": .object(["enum": .array(ScopeKind.allCases.map { .string($0.rawValue) })]),
                "score": .object([
                    "additionalProperties": .boolean(false),
                    "properties": .object([
                        "passed": .object(["minimum": .number("0"), "type": .string("integer")]),
                        "total": .object(["minimum": .number("0"), "type": .string("integer")]),
                    ]),
                    "required": .array([.string("passed"), .string("total")]),
                    "type": .string("object"),
                ]),
                "verdict": .object(["enum": .array(Verdict.allCases.map { .string($0.rawValue) })]),
            ]),
            "required": .array([
                .string("catalogDigest"),
                .string("diagnostics"),
                .string("executionCount"),
                .string("faults"),
                .string("run"),
                .string("schema"),
                .string("scope"),
                .string("score"),
                .string("verdict"),
            ]),
            "type": .string("object"),
        ])
    }

    private static func catalogValue(_ catalog: EvidenceCatalog) -> JSONValue {
        return .object([
            "inputContinuity": .string(catalog.inputContinuity.rawValue),
            "runtimePipeline": .string(catalog.runtimePipeline.rawValue),
            "preservationClaims": .array(catalog.preservationClaims.definitions.map { claim in
                .object([
                    "id": .string(claim.id.rawValue),
                    "name": .string(claim.name),
                ])
            }),
            "detectionClaims": .array(catalog.detectionClaims.definitions.map { claim in
                .object([
                    "id": .string(claim.id.rawValue),
                    "name": .string(claim.name),
                ])
            }),
            "claimObservations": .array(catalog.claimObservations.map { observation in
                .object([
                    "claim": .string(observation.claim.rawValue),
                    "world": .string(observation.world.rawValue),
                    "status": .string(observation.status.rawValue),
                    "diagnostic": diagnosticValue(observation.diagnostic),
                ])
            }),
            "executionCount": .number(String(catalog.executionCount.rawValue)),
            "failures": .array(catalog.failures.map(failureValue)),
            "lawObservations": .array(catalog.lawObservations.map {
                .object([
                    "code": .string($0.code.rawValue),
                    "status": .string($0.status.rawValue),
                    "diagnostic": diagnosticValue($0.diagnostic),
                ])
            }),
            "mutationObservations": .array(catalog.mutationObservations.map { observation in
                .object([
                    "mutant": .string(observation.mutant.rawValue),
                    "world": .string(observation.world.rawValue),
                    "reached": .string(observation.reached.rawValue),
                    "infected": .string(observation.infected.rawValue),
                    "detected": .string(observation.detected.rawValue),
                ])
            }),
            "mutants": .array(catalog.mutants.map { .string($0.rawValue) }),
            "review": .object([
                "status": .string(catalog.review.status.rawValue),
                "evidence": digestValue(catalog.review.evidence),
            ]),
            "run": .string(catalog.run.rawValue),
            "scope": .string(catalog.scope.rawValue),
            "schemaObservations": .array(catalog.schemaObservations.map {
                .object([
                    "status": .string($0.status.rawValue),
                    "version": .number(String($0.version.rawValue)),
                ])
            }),
            "worlds": .array(catalog.worlds.definitions.map(worldValue)),
        ])
    }

    private static func worldValue(_ declared: DeclaredWorld) -> JSONValue {
        switch declared {
        case .unmodeledHost(let id):
            return .object([
                "kind": .string("unmodeled-host"),
                "id": .string(id.rawValue),
            ])
        case .modeled(let world):
            return .object([
                "kind": .string("modeled"),
                "id": .string(world.id.rawValue),
                "build": .string(world.build.rawValue),
                "operatingSystem": .string(world.operatingSystem.rawValue),
                "device": .object([
                    "id": .string(world.device.id.rawValue),
                    "family": .string(world.device.family.rawValue),
                ]),
                "locale": .string(world.locale.rawValue),
                "layoutDirection": .string(world.layoutDirection.rawValue),
                "appearance": .string(world.appearance.rawValue),
                "accessibility": .string(world.accessibility.rawValue),
                "permission": .object([
                    "kind": .string(world.permission.kind.rawValue),
                    "state": .string(world.permission.state.rawValue),
                ]),
                "location": .string(world.location.rawValue),
                "biometrics": .string(world.biometrics.rawValue),
                "lifecycle": .string(world.lifecycle.rawValue),
                "data": .string(world.data.rawValue),
                "serviceFault": .string(world.serviceFault.rawValue),
                "cancellation": .string(world.cancellation.rawValue),
                "schedule": .object([
                    "id": .string(world.schedule.id.rawValue),
                    "decisions": .array(world.schedule.decisions.map { .number(String($0)) }),
                ]),
            ])
        }
    }

    private static func digestValue(_ digest: Digest?) -> JSONValue {
        return switch digest {
        case .some(let value):
            .string(value.rawValue)
        case .none:
            .null
        }
    }

    private static func diagnosticValue(_ diagnostic: Diagnostic?) -> JSONValue {
        switch diagnostic {
        case .some(let value):
            return diagnosticValue(value)
        case .none:
            return .null
        }
    }

    private static func diagnosticValue(_ diagnostic: Diagnostic) -> JSONValue {
        return .object([
            "code": .string(diagnostic.code.rawValue),
            "subject": .string(diagnostic.subject),
            "detail": .string(diagnostic.detail),
        ])
    }

    private static func failureValue(_ failure: ExecutionFailure) -> JSONValue {
        switch failure {
        case .clean(let clean):
            switch clean {
            case .preservationViolation(let claim, let world):
                return .object([
                    "kind": .string("preservation-violation"),
                    "claim": .string(claim.rawValue),
                    "world": .string(world.rawValue),
                ])
            case .baselineTestFailed(let test, let world):
                return .object([
                    "kind": .string("baseline-test-failed"),
                    "test": .string(test.rawValue),
                    "world": .string(world.rawValue),
                ])
            case .baselineCrashed(let test, let world):
                return .object([
                    "kind": .string("baseline-crashed"),
                    "test": .string(test.rawValue),
                    "world": .string(world.rawValue),
                ])
            }
        case .mutant(let mutant):
            switch mutant {
            case .survived(let mutant, let claim):
                return .object([
                    "kind": .string("mutant-survived"),
                    "mutant": .string(mutant.rawValue),
                    "claim": .string(claim.rawValue),
                ])
            case .notReached(let mutant):
                return .object(["kind": .string("mutant-not-reached"), "mutant": .string(mutant.rawValue)])
            case .notInfected(let mutant):
                return .object(["kind": .string("mutant-not-infected"), "mutant": .string(mutant.rawValue)])
            case .compilerRejected(let mutant):
                return .object(["kind": .string("mutant-compiler-rejected"), "mutant": .string(mutant.rawValue)])
            case .equivalentWithoutProof(let mutant):
                return .object(["kind": .string("mutant-equivalence-unproved"), "mutant": .string(mutant.rawValue)])
            }
        case .apparatus(let apparatus):
            let kind: String
            let diagnostic: Diagnostic
            switch apparatus {
            case .process(let value):
                kind = "apparatus-process"
                diagnostic = value
            case .codec(let value):
                kind = "apparatus-codec"
                diagnostic = value
            case .store(let value):
                kind = "apparatus-store"
                diagnostic = value
            case .toolchain(let value):
                kind = "apparatus-toolchain"
                diagnostic = value
            case .resourceOwnership(let value):
                kind = "apparatus-resource-ownership"
                diagnostic = value
            case .incompleteCatalog(let value):
                kind = "apparatus-incomplete-catalog"
                diagnostic = value
            }
            return .object(["kind": .string(kind), "diagnostic": diagnosticValue(diagnostic)])
        }
    }
}
