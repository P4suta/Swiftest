public enum ScopeKind: String, CaseIterable, Sendable {
    case complete
    case change
    case scoped
}

public enum ProofMode: String, CaseIterable, Sendable {
    case enabled
    case disabled
}

public enum Verdict: String, CaseIterable, Sendable {
    case assured = "ASSURED"
    case changeAssured = "CHANGE_ASSURED"
    case scopeAssured = "SCOPE_ASSURED"
    case unsettled = "UNSETTLED"
    case gaps = "GAPS"
    case gapsAndUnsettled = "GAPS+UNSETTLED"
    case invalid = "INVALID"
}

public enum ReviewStatus: String, CaseIterable, Sendable {
    case pending
    case accepted
    case rejected
}

public struct IndependentReview: Equatable, Sendable {
    public let status: ReviewStatus
    public let evidence: Digest?

    public init(status: ReviewStatus, evidence: Digest?) {
        self.status = status
        self.evidence = evidence
    }
}

public struct MutationObservation: Equatable, Sendable {
    public let mutant: MutantID
    public let reached: ObservationStatus
    public let infected: ObservationStatus
    public let detected: ObservationStatus

    public init(
        mutant: MutantID,
        reached: ObservationStatus,
        infected: ObservationStatus,
        detected: ObservationStatus
    ) {
        self.mutant = mutant
        self.reached = reached
        self.infected = infected
        self.detected = detected
    }
}

public struct LawObservation: Equatable, Sendable {
    public let code: String
    public let status: ObservationStatus

    public init(code: String, status: ObservationStatus) {
        self.code = code
        self.status = status
    }
}

public struct SchemaObservation: Equatable, Sendable {
    public let version: SchemaVersion
    public let status: ObservationStatus

    public init(version: SchemaVersion, status: ObservationStatus) {
        self.version = version
        self.status = status
    }
}

public struct EvidenceCatalog: Equatable, Sendable {
    public let run: RunID
    public let scope: ScopeKind
    public let preservationClaims: [ClaimID]
    public let detectionClaims: [ClaimID]
    public let worlds: [WorldID]
    public let mutants: [MutantID]
    public let claimObservations: [ClaimObservation]
    public let mutationObservations: [MutationObservation]
    public let lawObservations: [LawObservation]
    public let schemaObservations: [SchemaObservation]
    public let failures: [ExecutionFailure]
    public let review: IndependentReview
    public let executionCount: EvidenceCount

    public init(
        run: RunID,
        scope: ScopeKind,
        preservationClaims: [ClaimID],
        detectionClaims: [ClaimID],
        worlds: [WorldID],
        mutants: [MutantID],
        claimObservations: [ClaimObservation],
        mutationObservations: [MutationObservation],
        lawObservations: [LawObservation],
        schemaObservations: [SchemaObservation],
        failures: [ExecutionFailure],
        review: IndependentReview,
        executionCount: EvidenceCount
    ) {
        self.run = run
        self.scope = scope
        self.preservationClaims = preservationClaims
        self.detectionClaims = detectionClaims
        self.worlds = worlds
        self.mutants = mutants
        self.claimObservations = claimObservations
        self.mutationObservations = mutationObservations
        self.lawObservations = lawObservations
        self.schemaObservations = schemaObservations
        self.failures = failures
        self.review = review
        self.executionCount = executionCount
    }

    public var coverageGaps: [Diagnostic] {
        var gaps: [Diagnostic] = []
        if preservationClaims.isEmpty {
            gaps.append(Diagnostic(code: .missingEvidence, subject: "preservation-claims", detail: "none declared"))
        }
        if detectionClaims.isEmpty {
            gaps.append(Diagnostic(code: .missingEvidence, subject: "detection-claims", detail: "none declared"))
        }
        if worlds.isEmpty {
            gaps.append(Diagnostic(code: .missingEvidence, subject: "worlds", detail: "none executed"))
        }
        if mutants.isEmpty {
            gaps.append(Diagnostic(code: .missingEvidence, subject: "mutants", detail: "none executed"))
        }
        if executionCount.rawValue == 0 {
            gaps.append(Diagnostic(code: .missingEvidence, subject: "tests", detail: "none executed"))
        }
        if !schemaObservations.contains(where: { $0.version == .v2 && $0.status == .passed }) {
            gaps.append(Diagnostic(code: .missingEvidence, subject: "report-schema-v2", detail: "not validated"))
        }
        for observation in claimObservations where observation.status == .provenIrrelevant {
            gaps.append(Diagnostic(
                code: .missingEvidence,
                subject: observation.claim.rawValue + ":" + observation.world.rawValue,
                detail: "claim irrelevance has no proof certificate"
            ))
        }
        for observation in mutationObservations {
            if observation.reached != .passed || observation.infected != .passed || observation.detected != .passed {
                gaps.append(Diagnostic(
                    code: .missingEvidence,
                    subject: observation.mutant.rawValue,
                    detail: "mutation not detected after reach and infection"
                ))
            }
        }
        return gaps
    }

    public var hasApparatusFailure: Bool {
        failures.contains {
            if case .apparatus = $0 {
                return true
            }
            return false
        }
    }

    public var hasUnsettledEvidence: Bool {
        let cleanFailed = failures.contains {
            if case .clean = $0 {
                return true
            }
            return false
        }
        return cleanFailed || claimObservations.contains(where: { $0.status == .failed })
            || review.status != .accepted || review.evidence == nil
    }

    public var hasGapEvidence: Bool {
        let mutantFailed = failures.contains {
            if case .mutant = $0 {
                return true
            }
            return false
        }
        return mutantFailed || !coverageGaps.isEmpty
            || lawObservations.contains(where: { $0.status != .passed })
            || schemaObservations.contains(where: { $0.status != .passed })
    }
}

public enum Open: Sendable {}

public enum Closed: Sendable {}

public struct AuditedCatalog<Closure>: Sendable {
    public let evidence: EvidenceCatalog
    public let verdict: Verdict
    public let diagnostics: [Diagnostic]

    init(evidence: EvidenceCatalog, verdict: Verdict, diagnostics: [Diagnostic]) {
        self.evidence = evidence
        self.verdict = verdict
        self.diagnostics = diagnostics
    }
}

public enum AuditError: Error, Equatable, Sendable {
    case duplicateClaim(ClaimID)
    case duplicateWorld(WorldID)
    case duplicateMutant(MutantID)
    case unknownClaimObservation(ClaimID, WorldID)
    case duplicateClaimObservation(ClaimID, WorldID)
    case missingClaimObservation(ClaimID, WorldID)
    case unknownMutationObservation(MutantID)
    case duplicateMutationObservation(MutantID)
    case missingMutationObservation(MutantID)
    case duplicateLawObservation(String)
    case duplicateSchemaObservation(SchemaVersion)
    case missingLawObservation
    case missingSchemaObservation
}

public enum AuditKernel {
    public static func close(
        _ catalog: EvidenceCatalog
    ) throws(AuditError) -> AuditedCatalog<Closed> {
        try ensureUnique(catalog.preservationClaims + catalog.detectionClaims)
        try ensureUnique(catalog.worlds)
        try ensureUnique(catalog.mutants)

        let claims = Set(catalog.preservationClaims + catalog.detectionClaims)
        let worlds = Set(catalog.worlds)
        let mutants = Set(catalog.mutants)
        var observedClaims = Set<ClaimWorldPair>()
        for observation in catalog.claimObservations {
            if !claims.contains(observation.claim) || !worlds.contains(observation.world) {
                throw .unknownClaimObservation(observation.claim, observation.world)
            }
            let pair = ClaimWorldPair(claim: observation.claim, world: observation.world)
            if !observedClaims.insert(pair).inserted {
                throw .duplicateClaimObservation(observation.claim, observation.world)
            }
        }

        for claim in catalog.preservationClaims + catalog.detectionClaims {
            for world in catalog.worlds {
                if !observedClaims.contains(ClaimWorldPair(claim: claim, world: world)) {
                    throw .missingClaimObservation(claim, world)
                }
            }
        }

        var observedMutants = Set<MutantID>()
        for observation in catalog.mutationObservations {
            if !mutants.contains(observation.mutant) {
                throw .unknownMutationObservation(observation.mutant)
            }
            if !observedMutants.insert(observation.mutant).inserted {
                throw .duplicateMutationObservation(observation.mutant)
            }
        }
        for mutant in catalog.mutants {
            if !observedMutants.contains(mutant) {
                throw .missingMutationObservation(mutant)
            }
        }

        if catalog.lawObservations.isEmpty {
            throw .missingLawObservation
        }
        var observedLaws = Set<String>()
        for observation in catalog.lawObservations {
            if !observedLaws.insert(observation.code).inserted {
                throw .duplicateLawObservation(observation.code)
            }
        }
        if catalog.schemaObservations.isEmpty {
            throw .missingSchemaObservation
        }
        var observedSchemas = Set<SchemaVersion>()
        for observation in catalog.schemaObservations {
            if !observedSchemas.insert(observation.version).inserted {
                throw .duplicateSchemaObservation(observation.version)
            }
        }

        let verdict = VerdictPolicy.decide(VerdictPolicy.inputs(for: catalog))

        var diagnostics = catalog.coverageGaps
        if catalog.review.status == .pending || catalog.review.evidence == nil {
            diagnostics.append(Diagnostic(code: .reviewMissing, subject: "review", detail: "independent review absent"))
        }
        return AuditedCatalog<Closed>(evidence: catalog, verdict: verdict, diagnostics: diagnostics)
    }
}

private struct ClaimWorldPair: Hashable {
    let claim: ClaimID
    let world: WorldID
}

private func ensureUnique(_ values: [ClaimID]) throws(AuditError) {
    var seen = Set<ClaimID>()
    for value in values {
        let inserted = seen.insert(value)
        if !inserted.inserted {
            throw .duplicateClaim(value)
        }
    }
}

private func ensureUnique(_ values: [WorldID]) throws(AuditError) {
    var seen = Set<WorldID>()
    for value in values {
        let inserted = seen.insert(value)
        if !inserted.inserted {
            throw .duplicateWorld(value)
        }
    }
}

private func ensureUnique(_ values: [MutantID]) throws(AuditError) {
    var seen = Set<MutantID>()
    for value in values {
        let inserted = seen.insert(value)
        if !inserted.inserted {
            throw .duplicateMutant(value)
        }
    }
}
