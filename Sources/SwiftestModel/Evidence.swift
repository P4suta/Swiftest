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
    case missingClaimObservation(ClaimID, WorldID)
    case missingMutationObservation(MutantID)
    case missingLawObservation
    case missingSchemaObservation
    case missingIndependentReview
}

public enum AuditKernel {
    public static func close(
        _ catalog: EvidenceCatalog
    ) throws(AuditError) -> AuditedCatalog<Closed> {
        try ensureUnique(catalog.preservationClaims + catalog.detectionClaims)
        try ensureUnique(catalog.worlds)
        try ensureUnique(catalog.mutants)

        for claim in catalog.preservationClaims + catalog.detectionClaims {
            for world in catalog.worlds {
                let found = catalog.claimObservations.contains {
                    $0.claim == claim && $0.world == world
                }
                if !found {
                    throw .missingClaimObservation(claim, world)
                }
            }
        }

        for mutant in catalog.mutants {
            if !catalog.mutationObservations.contains(where: { $0.mutant == mutant }) {
                throw .missingMutationObservation(mutant)
            }
        }

        if catalog.lawObservations.isEmpty {
            throw .missingLawObservation
        }
        if catalog.schemaObservations.isEmpty {
            throw .missingSchemaObservation
        }
        if catalog.review.status == .pending {
            throw .missingIndependentReview
        }

        let hasApparatusFailure = catalog.failures.contains {
            if case .apparatus = $0 {
                return true
            }
            return false
        }
        let hasUnsettled = catalog.failures.contains {
            if case .clean = $0 {
                return true
            }
            return false
        } || catalog.review.status == .rejected
        let hasGaps = catalog.failures.contains {
            if case .mutant = $0 {
                return true
            }
            return false
        } || catalog.lawObservations.contains(where: { $0.status == .failed })
            || catalog.schemaObservations.contains(where: { $0.status == .failed })

        let verdict: Verdict
        if hasApparatusFailure {
            verdict = .invalid
        } else if hasGaps && hasUnsettled {
            verdict = .gapsAndUnsettled
        } else if hasGaps {
            verdict = .gaps
        } else if hasUnsettled {
            verdict = .unsettled
        } else {
            switch catalog.scope {
            case .complete:
                verdict = .assured
            case .change:
                verdict = .changeAssured
            case .scoped:
                verdict = .scopeAssured
            }
        }

        return AuditedCatalog<Closed>(evidence: catalog, verdict: verdict, diagnostics: [])
    }
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
