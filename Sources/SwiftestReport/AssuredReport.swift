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
    case decisionMismatch(expected: Verdict, actual: Verdict)
}

public struct AssuredReport: Sendable {
    public let catalog: AuditedCatalog<Closed>
    public let faults: AuditedFaultCampaign
    public let score: AssuranceScore

    public init(
        catalog: AuditedCatalog<Closed>,
        faults: AuditedFaultCampaign
    ) throws(ReportError) {
        self.catalog = catalog
        self.faults = faults
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
    public let faultDigest: Digest
    public let faultScenarioCount: EvidenceCount
    public let injectedFaultCount: EvidenceCount

    public init(
        schema: SchemaVersion,
        run: RunID,
        scope: ScopeKind,
        verdict: Verdict,
        scorePassed: EvidenceCount,
        scoreTotal: EvidenceCount,
        executionCount: EvidenceCount,
        catalogDigest: Digest,
        faultDigest: Digest,
        faultScenarioCount: EvidenceCount,
        injectedFaultCount: EvidenceCount
    ) {
        self.schema = schema
        self.run = run
        self.scope = scope
        self.verdict = verdict
        self.scorePassed = scorePassed
        self.scoreTotal = scoreTotal
        self.executionCount = executionCount
        self.catalogDigest = catalogDigest
        self.faultDigest = faultDigest
        self.faultScenarioCount = faultScenarioCount
        self.injectedFaultCount = injectedFaultCount
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
        let value = JSONValue.object([
            "catalogDigest": .string(digest.rawValue),
            "executionCount": .number(String(report.catalog.evidence.executionCount.rawValue)),
            "faults": .object([
                "digest": .string(report.faults.digest.rawValue),
                "injectedPoints": .number(String(report.faults.injectedPointCount.rawValue)),
                "scenarios": .number(String(report.faults.scenarioCount.rawValue)),
            ]),
            "run": .string(report.catalog.evidence.run.rawValue),
            "schema": .number(String(SchemaVersion.v1.rawValue)),
            "scope": .string(report.catalog.evidence.scope.rawValue),
            "score": .object([
                "passed": .number(String(report.score.passed.rawValue)),
                "total": .number(String(report.score.total.rawValue)),
            ]),
            "verdict": .string(report.catalog.verdict.rawValue),
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
        let faultValue: JSONValue
        let scoreValue: JSONValue
        do {
            schemaRaw = try reader.requiredInteger("schema")
            runRaw = try reader.requiredString("run")
            scopeRaw = try reader.requiredString("scope")
            verdictRaw = try reader.requiredString("verdict")
            executionCountRaw = try reader.requiredInteger("executionCount")
            digestRaw = try reader.requiredString("catalogDigest")
            faultValue = try reader.requiredValue("faults")
            scoreValue = try reader.requiredValue("score")
            try reader.finish()
        } catch let error {
            throw .codec(error)
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
        let faultDigestRaw: String
        let faultScenarioCountRaw: Int
        let injectedFaultCountRaw: Int
        do {
            faultDigestRaw = try faultReader.requiredString("digest")
            injectedFaultCountRaw = try faultReader.requiredInteger("injectedPoints")
            faultScenarioCountRaw = try faultReader.requiredInteger("scenarios")
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
        if schema != .v1 {
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
        let passed: EvidenceCount
        let total: EvidenceCount
        let executionCount: EvidenceCount
        let faultScenarioCount: EvidenceCount
        let injectedFaultCount: EvidenceCount
        do {
            passed = try .nonnegative(passedRaw)
            total = try .nonnegative(totalRaw)
            executionCount = try .nonnegative(executionCountRaw)
            faultScenarioCount = try .nonnegative(faultScenarioCountRaw)
            injectedFaultCount = try .nonnegative(injectedFaultCountRaw)
        } catch let error {
            throw .score(error)
        }
        let digest: Digest
        let faultDigest: Digest
        do {
            digest = try .parse(digestRaw)
            faultDigest = try .parse(faultDigestRaw)
        } catch let error {
            throw .digest(error)
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
            faultDigest: faultDigest,
            faultScenarioCount: faultScenarioCount,
            injectedFaultCount: injectedFaultCount
        )
    }

    public static func schema() -> JSONValue {
        .object([
            "$schema": .string("https://json-schema.org/draft/2020-12/schema"),
            "additionalProperties": .boolean(false),
            "properties": .object([
                "catalogDigest": .object(["pattern": .string("^[0-9a-f]{64}$"), "type": .string("string")]),
                "executionCount": .object(["minimum": .number("0"), "type": .string("integer")]),
                "faults": .object([
                    "additionalProperties": .boolean(false),
                    "properties": .object([
                        "digest": .object(["pattern": .string("^[0-9a-f]{64}$"), "type": .string("string")]),
                        "injectedPoints": .object(["minimum": .number("0"), "type": .string("integer")]),
                        "scenarios": .object(["minimum": .number("1"), "type": .string("integer")]),
                    ]),
                    "required": .array([.string("digest"), .string("injectedPoints"), .string("scenarios")]),
                    "type": .string("object"),
                ]),
                "run": .object(["minLength": .number("1"), "type": .string("string")]),
                "schema": .object(["const": .number("1")]),
                "scope": .object(["enum": .array(ScopeKind.allCases.map { .string($0.rawValue) })]),
                "score": .object([
                    "additionalProperties": .boolean(false),
                    "required": .array([.string("passed"), .string("total")]),
                    "type": .string("object"),
                ]),
                "verdict": .object(["enum": .array(Verdict.allCases.map { .string($0.rawValue) })]),
            ]),
            "required": .array([
                .string("catalogDigest"),
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
        .object([
            "claims": .array((catalog.preservationClaims + catalog.detectionClaims).map { .string($0.rawValue) }),
            "executionCount": .number(String(catalog.executionCount.rawValue)),
            "laws": .array(catalog.lawObservations.map {
                .object(["code": .string($0.code), "status": .string($0.status.rawValue)])
            }),
            "mutants": .array(catalog.mutants.map { .string($0.rawValue) }),
            "run": .string(catalog.run.rawValue),
            "schemas": .array(catalog.schemaObservations.map {
                .object([
                    "status": .string($0.status.rawValue),
                    "version": .number(String($0.version.rawValue)),
                ])
            }),
            "worlds": .array(catalog.worlds.map { .string($0.rawValue) }),
        ])
    }
}
