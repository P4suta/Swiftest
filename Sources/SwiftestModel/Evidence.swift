public enum ScopeKind: String, CaseIterable, Sendable {
    case complete
    case change
    case scoped
}

public enum ProofMode: String, CaseIterable, Sendable {
    case enabled
    case disabled
}

public enum RuntimePipelineEvidence: String, CaseIterable, Sendable {
    case unverified
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
    public let world: WorldID
    public let reached: ObservationStatus
    public let infected: ObservationStatus
    public let detected: ObservationStatus

    public init(
        mutant: MutantID,
        world: WorldID,
        reached: ObservationStatus,
        infected: ObservationStatus,
        detected: ObservationStatus
    ) {
        self.mutant = mutant
        self.world = world
        self.reached = reached
        self.infected = infected
        self.detected = detected
    }

    public var isSuccessful: Bool {
        reached == .passed && infected == .passed && detected == .passed
    }
}

public struct LawObservation: Equatable, Sendable {
    public let code: LawCode
    public let status: ObservationStatus
    public let diagnostic: Diagnostic?

    public init(code: LawCode, status: ObservationStatus, diagnostic: Diagnostic? = nil) {
        self.code = code
        self.status = status
        self.diagnostic = diagnostic
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
    public let inputContinuity: FileEventContinuity
    public let runtimePipeline: RuntimePipelineEvidence
    public let preservationClaims: DeclaredClaims<Preservation>
    public let detectionClaims: DeclaredClaims<Detection>
    public let worlds: DeclaredWorlds
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
        inputContinuity: FileEventContinuity,
        runtimePipeline: RuntimePipelineEvidence,
        preservationClaims: DeclaredClaims<Preservation>,
        detectionClaims: DeclaredClaims<Detection>,
        worlds: DeclaredWorlds,
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
        self.inputContinuity = inputContinuity
        self.runtimePipeline = runtimePipeline
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
        switch inputContinuity {
        case .eventFree:
            gaps.append(Diagnostic(
                code: .missingEvidence,
                subject: "input-continuity",
                detail: "event observation and byte recheck do not prove absence of a transient source change"
            ))
        case .attributeAmbiguous:
            gaps.append(Diagnostic(
                code: .missingEvidence,
                subject: "input-continuity",
                detail: "attribute event cannot exclude a reversible source change"
            ))
        }
        switch runtimePipeline {
        case .unverified:
            gaps.append(Diagnostic(
                code: .missingEvidence,
                subject: "runtime-pipeline",
                detail: "build, baseline, and planned execution are not bound to runtime-issued receipts"
            ))
        }
        if preservationClaims.isEmpty {
            gaps.append(Diagnostic(code: .missingEvidence, subject: "preservation-claims", detail: "none declared"))
        }
        if detectionClaims.isEmpty {
            gaps.append(Diagnostic(code: .missingEvidence, subject: "detection-claims", detail: "none declared"))
        }
        if worlds.isEmpty {
            gaps.append(Diagnostic(code: .missingEvidence, subject: "worlds", detail: "none executed"))
        }
        for definition in worlds.definitions {
            if case .unmodeledHost(let id) = definition {
                gaps.append(Diagnostic(
                    code: .missingEvidence,
                    subject: id.rawValue,
                    detail: "host world axes are not modeled"
                ))
            }
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
            if !observation.isSuccessful {
                gaps.append(Diagnostic(
                    code: .missingEvidence,
                    subject: observation.mutant.rawValue + ":" + observation.world.rawValue,
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
        return cleanFailed || inputContinuity == .attributeAmbiguous
            || claimObservations.contains(where: { $0.status == .failed })
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
    case conflictingWorldDefinition(WorldID)
    case impossibleWorldDefinition(WorldID)
    case duplicateMutant(MutantID)
    case unknownClaimObservation(ClaimID, WorldID)
    case duplicateClaimObservation(ClaimID, WorldID)
    case missingClaimObservation(ClaimID, WorldID)
    case unknownMutationObservation(MutantID, WorldID)
    case duplicateMutationObservation(MutantID, WorldID)
    case missingMutationObservation(MutantID, WorldID)
    case duplicateLawObservation(LawCode)
    case duplicateSchemaObservation(SchemaVersion)
    case missingLawObservation(LawCode)
    case missingSchemaObservation
    case unknownPreservationFailure(ClaimID, WorldID)
    case unknownBaselineWorld(WorldID)
    case unknownMutantFailure(MutantID)
    case unknownDetectionFailure(ClaimID)
}

public enum AuditKernel {
    public static func close(
        _ catalog: EvidenceCatalog
    ) throws(AuditError) -> AuditedCatalog<Closed> {
        let claimIDs = Array(catalog.preservationClaims) + Array(catalog.detectionClaims)
        try ensureUnique(claimIDs, error: AuditError.duplicateClaim)
        var worldDefinitions: [WorldID: DeclaredWorld] = [:]
        for definition in catalog.worlds.definitions {
            let id = definition.id
            if let previous = worldDefinitions.updateValue(definition, forKey: id) {
                if previous == definition {
                    throw .duplicateWorld(id)
                }
                throw .conflictingWorldDefinition(id)
            }
            if case .modeled(let modeled) = definition, !modeled.isPhysicallyPossible {
                throw .impossibleWorldDefinition(id)
            }
        }
        try ensureUnique(catalog.mutants, error: AuditError.duplicateMutant)

        let claims = Set(claimIDs)
        let worlds = Set(catalog.worlds)
        let mutants = Set(catalog.mutants)
        let preservationClaims = Set(catalog.preservationClaims)
        let detectionClaims = Set(catalog.detectionClaims)
        for failure in catalog.failures {
            switch failure {
            case .clean(.preservationViolation(let claim, let world)):
                guard preservationClaims.contains(claim), worlds.contains(world) else {
                    throw .unknownPreservationFailure(claim, world)
                }
            case .clean(.baselineTestFailed(_, let world)), .clean(.baselineCrashed(_, let world)):
                guard worlds.contains(world) else {
                    throw .unknownBaselineWorld(world)
                }
            case .mutant(.survived(let mutant, let claim)):
                guard mutants.contains(mutant) else {
                    throw .unknownMutantFailure(mutant)
                }
                guard detectionClaims.contains(claim) else {
                    throw .unknownDetectionFailure(claim)
                }
            case .mutant(.notReached(let mutant)), .mutant(.notInfected(let mutant)),
                 .mutant(.compilerRejected(let mutant)), .mutant(.equivalentWithoutProof(let mutant)):
                guard mutants.contains(mutant) else {
                    throw .unknownMutantFailure(mutant)
                }
            case .apparatus:
                break
            }
        }
        var observedClaims = Set<WorldPoint<ClaimID>>()
        for observation in catalog.claimObservations {
            if !claims.contains(observation.claim) || !worlds.contains(observation.world) {
                throw .unknownClaimObservation(observation.claim, observation.world)
            }
            let pair = WorldPoint(member: observation.claim, world: observation.world)
            if !observedClaims.insert(pair).inserted {
                throw .duplicateClaimObservation(observation.claim, observation.world)
            }
        }

        for claim in claimIDs {
            for world in catalog.worlds {
                if !observedClaims.contains(WorldPoint(member: claim, world: world)) {
                    throw .missingClaimObservation(claim, world)
                }
            }
        }

        var observedMutants = Set<WorldPoint<MutantID>>()
        for observation in catalog.mutationObservations {
            if !mutants.contains(observation.mutant) || !worlds.contains(observation.world) {
                throw .unknownMutationObservation(observation.mutant, observation.world)
            }
            let point = WorldPoint(member: observation.mutant, world: observation.world)
            if !observedMutants.insert(point).inserted {
                throw .duplicateMutationObservation(observation.mutant, observation.world)
            }
        }
        for mutant in catalog.mutants {
            for world in catalog.worlds {
                if !observedMutants.contains(WorldPoint(member: mutant, world: world)) {
                    throw .missingMutationObservation(mutant, world)
                }
            }
        }

        var observedLaws = Set<LawCode>()
        for observation in catalog.lawObservations {
            if !observedLaws.insert(observation.code).inserted {
                throw .duplicateLawObservation(observation.code)
            }
        }
        for law in LawCode.allCases where !observedLaws.contains(law) {
            throw .missingLawObservation(law)
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

        var diagnostics = catalog.coverageGaps + catalog.failures.map(\.diagnostic)
        diagnostics.append(contentsOf: catalog.lawObservations.compactMap(\.diagnostic))
        if catalog.review.status == .pending || catalog.review.evidence == nil {
            diagnostics.append(Diagnostic(code: .reviewMissing, subject: "review", detail: "independent review absent"))
        }
        return AuditedCatalog<Closed>(evidence: catalog, verdict: verdict, diagnostics: diagnostics)
    }
}

package struct WorldPoint<Member: Hashable & Sendable>: Hashable, Sendable {
    package let member: Member
    let world: WorldID
}

private func ensureUnique<Value: Hashable>(
    _ values: [Value],
    error: (Value) -> AuditError
) throws(AuditError) {
    var seen = Set<Value>()
    for value in values {
        let inserted = seen.insert(value)
        if !inserted.inserted {
            throw error(value)
        }
    }
}
