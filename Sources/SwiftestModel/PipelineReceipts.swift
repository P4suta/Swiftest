package enum BuildResult: Equatable, Sendable {
    case completed(artifactDigest: Digest)
    case apparatusFailed(ApparatusFailure)
}

package enum BaselineTestResult: Equatable, Sendable {
    case passed(TestID)
    case failed(CleanFailure)
    case apparatusFailed(ApparatusFailure)
}

package enum PlannedExecutionResult: Equatable, Sendable {
    case world(WorldID)
    case mutant(MutantID, WorldID)
}

public struct BuildReceipt: Equatable, Sendable {
    let plan: FrozenPlan
    public let artifactDigest: Digest

    private init(plan: FrozenPlan, artifactDigest: Digest) {
        self.plan = plan
        self.artifactDigest = artifactDigest
    }

    package static func validated(
        plan: FrozenPlan,
        result: BuildResult
    ) throws(PipelineError) -> BuildReceipt {
        switch result {
        case .completed(let artifactDigest):
            return BuildReceipt(plan: plan, artifactDigest: artifactDigest)
        case .apparatusFailed(let failure):
            throw .buildFailed(failure)
        }
    }
}

public struct BaselineReceipt: Equatable, Sendable {
    let plan: FrozenPlan
    let discovery: DiscoveryCatalog
    public let transcriptDigest: Digest

    private init(plan: FrozenPlan, discovery: DiscoveryCatalog, transcriptDigest: Digest) {
        self.plan = plan
        self.discovery = discovery
        self.transcriptDigest = transcriptDigest
    }

    package static func validated(
        plan: FrozenPlan,
        discovery: DiscoveryCatalog,
        results: [BaselineTestResult],
        transcriptDigest: Digest
    ) throws(PipelineError) -> BaselineReceipt {
        guard !discovery.tests.isEmpty else {
            throw .emptyCatalog
        }
        let declared = Set(discovery.tests)
        guard declared.count == discovery.tests.count else {
            throw .planMismatch(.tests)
        }
        var passed = Set<TestID>()
        for result in results {
            switch result {
            case .passed(let test):
                guard declared.contains(test), passed.insert(test).inserted else {
                    throw .planMismatch(.tests)
                }
            case .failed(let failure):
                throw .baselineFailed(failure)
            case .apparatusFailed(let failure):
                throw .executionFailed(.apparatus(failure))
            }
        }
        guard passed == declared else {
            throw .planMismatch(.tests)
        }
        return BaselineReceipt(plan: plan, discovery: discovery, transcriptDigest: transcriptDigest)
    }
}

public struct ExecutionReceipt: Equatable, Sendable {
    let plan: FrozenPlan
    public let transcriptDigest: Digest
    public let executionCount: EvidenceCount

    private init(plan: FrozenPlan, transcriptDigest: Digest, executionCount: EvidenceCount) {
        self.plan = plan
        self.transcriptDigest = transcriptDigest
        self.executionCount = executionCount
    }

    package static func validated(
        plan: FrozenPlan,
        results: [PlannedExecutionResult],
        transcriptDigest: Digest,
        executionCount: EvidenceCount
    ) throws(PipelineError) -> ExecutionReceipt {
        guard !plan.worlds.isEmpty else {
            throw .planMismatch(.worlds)
        }
        guard executionCount > .zero else {
            throw .planMismatch(.executionCount)
        }
        let declaredWorlds = Set(plan.worlds)
        let declaredMutants = Set(plan.mutants)
        guard declaredWorlds.count == plan.worlds.count else {
            throw .planMismatch(.worlds)
        }
        guard declaredMutants.count == plan.mutants.count else {
            throw .planMismatch(.mutants)
        }
        var observedWorlds = Set<WorldID>()
        var observedMutants = Set<WorldPoint<MutantID>>()
        for result in results {
            switch result {
            case .world(let world):
                guard declaredWorlds.contains(world), observedWorlds.insert(world).inserted else {
                    throw .planMismatch(.worlds)
                }
            case .mutant(let mutant, let world):
                guard declaredMutants.contains(mutant), declaredWorlds.contains(world),
                    observedMutants.insert(WorldPoint(member: mutant, world: world)).inserted else {
                    throw .planMismatch(.mutants)
                }
            }
        }
        guard observedWorlds == declaredWorlds else {
            throw .planMismatch(.worlds)
        }
        for mutant in plan.mutants {
            for world in plan.worlds {
                guard observedMutants.contains(WorldPoint(member: mutant, world: world)) else {
                    throw .planMismatch(.mutants)
                }
            }
        }
        return ExecutionReceipt(
            plan: plan,
            transcriptDigest: transcriptDigest,
            executionCount: executionCount
        )
    }
}
