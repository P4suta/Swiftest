public enum Discovered: Sendable {}

public enum Planned: Sendable {}

public enum Frozen: Sendable {}

public enum Built: Sendable {}

public enum BaselinePassed: Sendable {}

public enum Executed: Sendable {}

public enum Recorded: Sendable {}

public enum Audited: Sendable {}

public enum PipelineError: Error, Equatable, Sendable {
    case emptyCatalog
    case planNotFrozen
    case planMismatch(PlanMismatch)
    case buildFailed(ApparatusFailure)
    case baselineFailed(CleanFailure)
    case executionFailed(ExecutionFailure)
    case recordFailed(ApparatusFailure)
    case auditFailed(AuditError)
}

public enum PlanMismatch: Equatable, Sendable {
    case run
    case preservationClaims
    case detectionClaims
    case worlds
    case mutants
}

public struct DiscoveryCatalog: Equatable, Sendable {
    public let preservationClaims: [ClaimID]
    public let detectionClaims: [ClaimID]
    public let tests: [TestID]

    public init(
        preservationClaims: [ClaimID],
        detectionClaims: [ClaimID],
        tests: [TestID]
    ) {
        self.preservationClaims = preservationClaims
        self.detectionClaims = detectionClaims
        self.tests = tests
    }
}

public struct FrozenPlan: Equatable, Sendable {
    public let run: RunID
    public let worlds: [WorldID]
    public let mutants: [MutantID]
    public let digest: Digest

    public init(run: RunID, worlds: [WorldID], mutants: [MutantID], digest: Digest) {
        self.run = run
        self.worlds = worlds
        self.mutants = mutants
        self.digest = digest
    }
}

public struct PipelinePayload: Equatable, Sendable {
    public var discovery: DiscoveryCatalog
    public var plan: FrozenPlan?
    public var evidence: EvidenceCatalog?

    public init(discovery: DiscoveryCatalog) {
        self.discovery = discovery
        self.plan = nil
        self.evidence = nil
    }
}

public struct Pipeline<State>: ~Copyable {
    var payload: PipelinePayload

    init(payload: PipelinePayload) {
        self.payload = payload
    }
}

extension Pipeline where State == Discovered {
    public static func discover(_ catalog: DiscoveryCatalog) -> Pipeline<Discovered> {
        Pipeline<Discovered>(payload: PipelinePayload(discovery: catalog))
    }

    public consuming func plan() throws(PipelineError) -> Pipeline<Planned> {
        if payload.discovery.tests.isEmpty {
            throw .emptyCatalog
        }
        return Pipeline<Planned>(payload: payload)
    }
}

extension Pipeline where State == Planned {
    public consuming func freeze(_ plan: FrozenPlan) -> Pipeline<Frozen> {
        var next = payload
        next.plan = plan
        return Pipeline<Frozen>(payload: next)
    }
}

extension Pipeline where State == Frozen {
    public consuming func built() throws(PipelineError) -> Pipeline<Built> {
        if payload.plan == nil {
            throw .planNotFrozen
        }
        return Pipeline<Built>(payload: payload)
    }
}

extension Pipeline where State == Built {
    public consuming func baselinePassed() -> Pipeline<BaselinePassed> {
        Pipeline<BaselinePassed>(payload: payload)
    }
}

extension Pipeline where State == BaselinePassed {
    public consuming func executed() -> Pipeline<Executed> {
        Pipeline<Executed>(payload: payload)
    }
}

extension Pipeline where State == Executed {
    public consuming func record(_ evidence: EvidenceCatalog) -> Pipeline<Recorded> {
        var next = payload
        next.evidence = evidence
        return Pipeline<Recorded>(payload: next)
    }
}

extension Pipeline where State == Recorded {
    public consuming func audit() throws(PipelineError) -> Pipeline<Audited> {
        guard let evidence = payload.evidence else {
            throw .recordFailed(.incompleteCatalog(
                Diagnostic(code: .missingEvidence, subject: "pipeline", detail: "recorded evidence is absent")
            ))
        }
        try validateRecordedEvidence(payload, evidence: evidence)
        do {
            let validated = try AuditKernel.close(evidence)
            consumeValidatedCatalog(validated)
            return Pipeline<Audited>(payload: payload)
        } catch let error {
            throw .auditFailed(error)
        }
    }
}

private func consumeValidatedCatalog(_ catalog: AuditedCatalog<Closed>) {
    if catalog.evidence.run.rawValue.isEmpty {
        preconditionFailure("validated run identifier is empty")
    }
}

extension Pipeline where State == Audited {
    public consuming func closedCatalog() throws(PipelineError) -> AuditedCatalog<Closed> {
        guard let evidence = payload.evidence else {
            throw .recordFailed(.incompleteCatalog(
                Diagnostic(code: .missingEvidence, subject: "pipeline", detail: "audited evidence is absent")
            ))
        }
        try validateRecordedEvidence(payload, evidence: evidence)
        do {
            return try AuditKernel.close(evidence)
        } catch let error {
            throw .auditFailed(error)
        }
    }
}

private func validateRecordedEvidence(
    _ payload: PipelinePayload,
    evidence: EvidenceCatalog
) throws(PipelineError) {
    guard let plan = payload.plan else {
        throw .planNotFrozen
    }
    if evidence.run != plan.run {
        throw .planMismatch(.run)
    }
    if evidence.preservationClaims != payload.discovery.preservationClaims {
        throw .planMismatch(.preservationClaims)
    }
    if evidence.detectionClaims != payload.discovery.detectionClaims {
        throw .planMismatch(.detectionClaims)
    }
    if evidence.worlds != plan.worlds {
        throw .planMismatch(.worlds)
    }
    if evidence.mutants != plan.mutants {
        throw .planMismatch(.mutants)
    }
}
