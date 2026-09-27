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
    case tests
    case worlds
    case mutants
    case receipt
    case executionCount
}

public struct DiscoveryCatalog: Equatable, Sendable {
    public let preservationClaims: DeclaredClaims<Preservation>
    public let detectionClaims: DeclaredClaims<Detection>
    public let tests: [TestID]

    public init(
        preservationClaims: DeclaredClaims<Preservation>,
        detectionClaims: DeclaredClaims<Detection>,
        tests: [TestID]
    ) {
        self.preservationClaims = preservationClaims
        self.detectionClaims = detectionClaims
        self.tests = tests
    }
}

public struct FrozenPlan: Equatable, Sendable {
    public let run: RunID
    public let worlds: DeclaredWorlds
    public let mutants: [MutantID]
    public let digest: Digest

    public init(run: RunID, worlds: DeclaredWorlds, mutants: [MutantID], digest: Digest) {
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
    package var buildReceipt: BuildReceipt?
    package var baselineReceipt: BaselineReceipt?
    package var executionReceipt: ExecutionReceipt?

    public init(discovery: DiscoveryCatalog) {
        self.discovery = discovery
        self.plan = nil
        self.evidence = nil
        self.buildReceipt = nil
        self.baselineReceipt = nil
        self.executionReceipt = nil
    }
}

public struct Pipeline<State>: ~Copyable {
    var payload: PipelinePayload
    var auditedCatalog: AuditedCatalog<Closed>?

    init(payload: PipelinePayload, auditedCatalog: AuditedCatalog<Closed>? = nil) {
        self.payload = payload
        self.auditedCatalog = auditedCatalog
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
    public consuming func built(receipt: BuildReceipt) throws(PipelineError) -> Pipeline<Built> {
        guard let plan = payload.plan else {
            throw .planNotFrozen
        }
        guard receipt.plan == plan else {
            throw .planMismatch(.receipt)
        }
        var next = payload
        next.buildReceipt = receipt
        return Pipeline<Built>(payload: next)
    }
}

extension Pipeline where State == Built {
    public consuming func baselinePassed(
        receipt: BaselineReceipt
    ) throws(PipelineError) -> Pipeline<BaselinePassed> {
        guard let plan = payload.plan, payload.buildReceipt != nil else {
            throw .planNotFrozen
        }
        guard receipt.plan == plan && receipt.discovery == payload.discovery else {
            throw .planMismatch(.receipt)
        }
        var next = payload
        next.baselineReceipt = receipt
        return Pipeline<BaselinePassed>(payload: next)
    }
}

extension Pipeline where State == BaselinePassed {
    public consuming func executed(receipt: ExecutionReceipt) throws(PipelineError) -> Pipeline<Executed> {
        guard let plan = payload.plan, payload.baselineReceipt != nil else {
            throw .planNotFrozen
        }
        guard receipt.plan == plan else {
            throw .planMismatch(.receipt)
        }
        var next = payload
        next.executionReceipt = receipt
        return Pipeline<Executed>(payload: next)
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
            return Pipeline<Audited>(payload: payload, auditedCatalog: validated)
        } catch let error {
            throw .auditFailed(error)
        }
    }
}

extension Pipeline where State == Audited {
    public consuming func closedCatalog() throws(PipelineError) -> AuditedCatalog<Closed> {
        guard let catalog = auditedCatalog else {
            throw .recordFailed(.incompleteCatalog(
                Diagnostic(code: .missingEvidence, subject: "pipeline", detail: "audited catalog is absent")
            ))
        }
        return catalog
    }
}

private func validateRecordedEvidence(
    _ payload: PipelinePayload,
    evidence: EvidenceCatalog
) throws(PipelineError) {
    guard let plan = payload.plan else {
        throw .planNotFrozen
    }
    guard let execution = payload.executionReceipt,
        payload.buildReceipt != nil,
        payload.baselineReceipt != nil else {
        throw .recordFailed(.incompleteCatalog(Diagnostic(
            code: .missingEvidence,
            subject: "pipeline-receipts",
            detail: "build, baseline, or execution receipt is absent"
        )))
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
    if evidence.executionCount != execution.executionCount {
        throw .planMismatch(.executionCount)
    }
}
