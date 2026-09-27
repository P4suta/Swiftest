import CryptoKit
import Foundation
import SwiftestModel
import Testing

@Test
func declaredClaimsRetainPolarityAndDeclarationOrder() throws {
    let first = try Claim<Preservation>.preservation(
        id: ClaimID.parse("preservation-first"),
        name: "first"
    )
    let second = try Claim<Preservation>.preservation(
        id: ClaimID.parse("preservation-second"),
        name: "second"
    )
    let detection = try Claim<Detection>.detection(
        id: ClaimID.parse("detection-first"),
        name: "detect"
    )
    let preservationClaims = DeclaredClaims<Preservation>.from([first, second])
    let detectionClaims = DeclaredClaims<Detection>.from([detection])
    let renamed = try Claim<Preservation>.preservation(
        id: first.id,
        name: "renamed"
    )
    #expect(Array(preservationClaims) == [first.id, second.id])
    #expect(Array(detectionClaims) == [detection.id])
    #expect(preservationClaims.definitions == [first, second])
    #expect(detectionClaims.definitions == [detection])
    #expect(DeclaredClaims<Preservation>.from([first]) != DeclaredClaims<Preservation>.from([renamed]))
}

@Test
func nominalValuesRejectInvalidInputAndDigestCanonically() throws {
    let run = try RunID.parse("run-1")
    #expect(run.rawValue == "run-1")
    do {
        let invalid = try RunID.parse("")
        Issue.record("unexpected identifier")
        #expect(invalid.rawValue.isEmpty)
    } catch let error {
        #expect(error == .empty)
    }
    let digest = try Digest.sha256(Data("abc".utf8))
    #expect(digest.rawValue == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}

@Test
func artifactPathsRejectAliasesAndTraversal() throws {
    for (input, expected) in [
        ("a/../b", ArtifactPathError.parentTraversal),
        ("a/./b", .selfTraversal),
        ("a//b", .emptySegment),
        ("a/", .emptySegment),
    ] {
        do {
            let path = try ArtifactPath.parse(input)
            Issue.record("noncanonical path was accepted")
            #expect(path.rawValue.isEmpty)
        } catch let error {
            #expect(error == expected)
        }
    }
}

@Test
func artifactPathOracleCoversEveryRejectionKind() {
    let lines = ArtifactPathOracle.text().split(separator: "\n")
    #expect(lines.count == 9)
    #expect(lines.first == "path\tempty\tempty")
    #expect(lines.last == "path\tplain\taccepted")
}

@Test
func firstPartySHA256MatchesAppleAcrossBlockBoundaries() throws {
    for length in [0, 1, 55, 56, 63, 64, 65, 127, 128, 129, 1024] {
        let bytes = (0..<length).map { UInt8($0 % 251) }
        let data = Data(bytes)
        let reference = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let observed = try Digest.sha256(data)
        #expect(observed.rawValue == reference)
    }
}

@Test
func auditSeparatesInvalidGapsAndUnsettled() throws {
    let assured = try AuditKernel.close(catalog(failures: []))
    #expect(assured.verdict == .gaps)
    #expect(assured.diagnostics.contains(where: { $0.subject == "input-continuity" }))
    let gap = try AuditKernel.close(catalog(failures: [
        .mutant(.notReached(try MutantID.parse("mutant-1")))
    ]))
    #expect(gap.verdict == .gaps)
    let unsettled = try AuditKernel.close(catalog(failures: [
        .clean(.baselineTestFailed(try TestID.parse("test-1"), try WorldID.parse("world-1")))
    ]))
    #expect(unsettled.verdict == .gapsAndUnsettled)
    let invalid = try AuditKernel.close(catalog(failures: [
        .apparatus(.toolchain(Diagnostic(
            code: .apparatusFailed,
            subject: "toolchain",
            detail: "mismatch"
        )))
    ]))
    #expect(invalid.verdict == .invalid)
    #expect(invalid.diagnostics.contains(Diagnostic(
        code: .apparatusFailed,
        subject: "toolchain",
        detail: "mismatch"
    )))
    #expect(gap.diagnostics.contains(where: { $0.code == .mutationUnreached }))
    #expect(unsettled.diagnostics.contains(where: { $0.code == .baselineFailed }))
}

@Test
func forgeableCompleteCatalogRemainsUnassuredWithoutInputAndRuntimeProof() throws {
    let forged = try catalog(failures: [])
    #expect(forged.preservationClaims.count == 1)
    #expect(forged.detectionClaims.count == 1)
    #expect(forged.worlds.count == 1)
    #expect(forged.mutants.count == 1)
    #expect(forged.claimObservations.allSatisfy { $0.status == .passed })
    #expect(forged.mutationObservations.allSatisfy {
        $0.reached == .passed && $0.infected == .passed && $0.detected == .passed
    })
    #expect(forged.lawObservations.count == LawCode.allCases.count)
    #expect(forged.lawObservations.allSatisfy { $0.status == .passed })
    #expect(forged.schemaObservations == [SchemaObservation(version: .v2, status: .passed)])
    #expect(forged.review.status == .accepted)
    #expect(forged.review.evidence != nil)
    #expect(forged.executionCount.rawValue == 1)
    #expect(forged.failures.isEmpty)
    #expect(!forged.hasApparatusFailure)
    #expect(!forged.hasUnsettledEvidence)
    #expect(forged.runtimePipeline == .unverified)
    #expect(forged.coverageGaps.count == 3)
    #expect(forged.coverageGaps.map(\.subject) == ["input-continuity", "runtime-pipeline", "world-1"])
    let closed = try AuditKernel.close(forged)
    #expect(closed.verdict == .gaps)
    #expect(closed.diagnostics == forged.coverageGaps)
}

@Test
func ambiguousAttributeEventCannotProduceAssuredVerdict() throws {
    let base = try catalog(failures: [])
    let ambiguous = EvidenceCatalog(
        run: base.run,
        scope: base.scope,
        inputContinuity: .attributeAmbiguous,
        runtimePipeline: base.runtimePipeline,
        preservationClaims: base.preservationClaims,
        detectionClaims: base.detectionClaims,
        worlds: base.worlds,
        mutants: base.mutants,
        claimObservations: base.claimObservations,
        mutationObservations: base.mutationObservations,
        lawObservations: base.lawObservations,
        schemaObservations: base.schemaObservations,
        failures: base.failures,
        review: base.review,
        executionCount: base.executionCount
    )
    let audited = try AuditKernel.close(ambiguous)
    #expect(audited.verdict == .gapsAndUnsettled)
    #expect(audited.diagnostics.contains(where: { $0.subject == "input-continuity" }))
}

@Test
func pipelineReachesAuditedOnlyThroughEveryState() throws {
    let evidence = try catalog(failures: [])
    let discovery = DiscoveryCatalog(
        preservationClaims: evidence.preservationClaims,
        detectionClaims: evidence.detectionClaims,
        tests: [try TestID.parse("test-1")]
    )
    let plan = FrozenPlan(
        run: evidence.run,
        worlds: evidence.worlds,
        mutants: evidence.mutants,
        digest: try Digest.sha256(Data("plan".utf8))
    )
    let discovered = Pipeline<Discovered>.discover(discovery)
    let planned = try discovered.plan()
    let frozen = planned.freeze(plan)
    let receipts = try structuralReceipts(
        plan: plan,
        discovery: discovery,
        executionCount: evidence.executionCount
    )
    let built = try frozen.built(receipt: receipts.build)
    let baseline = try built.baselinePassed(receipt: receipts.baseline)
    let executed = try baseline.executed(receipt: receipts.execution)
    let recorded = executed.record(evidence)
    let audited = try recorded.audit()
    let closed = try audited.closedCatalog()
    #expect(closed.verdict == .gaps)
}

@Test
func pipelineRejectsEvidenceThatDiffersFromFrozenPlan() throws {
    let evidence = try catalog(failures: [])
    let discovery = DiscoveryCatalog(
        preservationClaims: evidence.preservationClaims,
        detectionClaims: evidence.detectionClaims,
        tests: [try TestID.parse("test-1")]
    )
    let plan = FrozenPlan(
        run: try RunID.parse("different-run"),
        worlds: evidence.worlds,
        mutants: evidence.mutants,
        digest: try Digest.sha256(Data("plan".utf8))
    )
    let discovered = Pipeline<Discovered>.discover(discovery)
    let planned = try discovered.plan()
    let frozen = planned.freeze(plan)
    let receipts = try structuralReceipts(
        plan: plan,
        discovery: discovery,
        executionCount: evidence.executionCount
    )
    let built = try frozen.built(receipt: receipts.build)
    let baseline = try built.baselinePassed(receipt: receipts.baseline)
    let executed = try baseline.executed(receipt: receipts.execution)
    let recorded = executed.record(evidence)
    do {
        let audited = try recorded.audit()
        let closed = try audited.closedCatalog()
        Issue.record("mismatched plan was accepted")
        #expect(closed.verdict == .invalid)
    } catch let error {
        #expect(error == .planMismatch(.run))
    }
}

@Test
func pipelineRejectsModeledWorldDefinitionChangedAfterFreeze() throws {
    let base = try catalog(failures: [])
    let worldID = base.worlds[0]
    let plannedWorlds = DeclaredWorlds.from([try modeledWorld(id: worldID, locale: .englishUnitedStates)])
    let recordedWorlds = DeclaredWorlds.from([try modeledWorld(id: worldID, locale: .japaneseJapan)])
    let evidence = EvidenceCatalog(
        run: base.run,
        scope: base.scope,
        inputContinuity: base.inputContinuity,
        runtimePipeline: base.runtimePipeline,
        preservationClaims: base.preservationClaims,
        detectionClaims: base.detectionClaims,
        worlds: recordedWorlds,
        mutants: base.mutants,
        claimObservations: base.claimObservations,
        mutationObservations: base.mutationObservations,
        lawObservations: base.lawObservations,
        schemaObservations: base.schemaObservations,
        failures: base.failures,
        review: base.review,
        executionCount: base.executionCount
    )
    let discovery = DiscoveryCatalog(
        preservationClaims: base.preservationClaims,
        detectionClaims: base.detectionClaims,
        tests: [try TestID.parse("test-1")]
    )
    let plan = FrozenPlan(
        run: base.run,
        worlds: plannedWorlds,
        mutants: base.mutants,
        digest: try Digest.sha256(Data("world-definition-plan".utf8))
    )
    let receipts = try structuralReceipts(plan: plan, discovery: discovery, executionCount: base.executionCount)
    let frozen = try Pipeline<Discovered>.discover(discovery).plan().freeze(plan)
    let built = try frozen.built(receipt: receipts.build)
    let baseline = try built.baselinePassed(receipt: receipts.baseline)
    let executed = try baseline.executed(receipt: receipts.execution)
    let recorded = executed.record(evidence)
    do {
        let audited = try recorded.audit()
        let closed = try audited.closedCatalog()
        Issue.record("changed modeled world was accepted")
        #expect(closed.verdict == .invalid)
    } catch let error {
        #expect(error == .planMismatch(.worlds))
    }
}

@Test
func emptyEvidenceCannotProduceAssuredVerdict() throws {
    let empty = EvidenceCatalog(
        run: try RunID.parse("run-empty"),
        scope: .complete,
        inputContinuity: .eventFree,
        runtimePipeline: .unverified,
        preservationClaims: .from([]),
        detectionClaims: .from([]),
        worlds: .from([]),
        mutants: [],
        claimObservations: [],
        mutationObservations: [],
        lawObservations: LawCode.allCases.map { LawObservation(code: $0, status: .passed) },
        schemaObservations: [SchemaObservation(version: .v2, status: .passed)],
        failures: [],
        review: IndependentReview(status: .pending, evidence: nil),
        executionCount: try EvidenceCount.nonnegative(0)
    )
    let audited = try AuditKernel.close(empty)
    #expect(audited.verdict == .gapsAndUnsettled)
    #expect(audited.diagnostics.contains(where: { $0.code == .reviewMissing }))
    #expect(audited.diagnostics.contains(where: { $0.subject == "tests" }))
}

@Test
func auditRequiresEveryClosedLawExactlyOnce() throws {
    guard let finalLaw = LawCode.allCases.last, let firstLaw = LawCode.allCases.first else {
        Issue.record("closed law domain was empty")
        return
    }
    let incomplete = try catalog(
        failures: [],
        lawObservations: LawCode.allCases.dropLast().map { LawObservation(code: $0, status: .passed) }
    )
    do {
        let audited = try AuditKernel.close(incomplete)
        Issue.record("missing law was accepted")
        #expect(audited.verdict == .invalid)
    } catch let error {
        #expect(error == .missingLawObservation(finalLaw))
    }
    let repeated = try catalog(
        failures: [],
        lawObservations: LawCode.allCases.map { LawObservation(code: $0, status: .passed) }
            + [LawObservation(code: firstLaw, status: .passed)]
    )
    do {
        let audited = try AuditKernel.close(repeated)
        Issue.record("duplicate law was accepted")
        #expect(audited.verdict == .invalid)
    } catch let error {
        #expect(error == .duplicateLawObservation(firstLaw))
    }
}

@Test
func unprovenClaimIrrelevanceCannotProduceAssuredVerdict() throws {
    let base = try catalog(failures: [])
    for unproven in base.claimObservations {
        let observations = base.claimObservations.map { observation in
            ClaimObservation(
                claim: observation.claim,
                world: observation.world,
                status: observation.claim == unproven.claim ? .provenIrrelevant : .passed,
                diagnostic: nil
            )
        }
        let evidence = EvidenceCatalog(
            run: base.run,
            scope: base.scope,
            inputContinuity: base.inputContinuity,
            runtimePipeline: base.runtimePipeline,
            preservationClaims: base.preservationClaims,
            detectionClaims: base.detectionClaims,
            worlds: base.worlds,
            mutants: base.mutants,
            claimObservations: observations,
            mutationObservations: base.mutationObservations,
            lawObservations: base.lawObservations,
            schemaObservations: base.schemaObservations,
            failures: base.failures,
            review: base.review,
            executionCount: base.executionCount
        )
        let audited = try AuditKernel.close(evidence)
        #expect(audited.verdict == .gaps)
        #expect(audited.diagnostics.contains(where: {
            $0.subject == unproven.claim.rawValue + ":" + unproven.world.rawValue
        }))
    }
}

@Test
func pipelineReceiptsRejectFailedBuildAndIncompleteExecution() throws {
    let evidence = try catalog(failures: [])
    let discovery = DiscoveryCatalog(
        preservationClaims: evidence.preservationClaims,
        detectionClaims: evidence.detectionClaims,
        tests: [try TestID.parse("test-1")]
    )
    let digest = try Digest.sha256(Data("structural-test".utf8))
    let plan = FrozenPlan(
        run: evidence.run,
        worlds: evidence.worlds,
        mutants: evidence.mutants,
        digest: digest
    )
    let apparatus = ApparatusFailure.process(Diagnostic(
        code: .apparatusFailed,
        subject: "build",
        detail: "build failed"
    ))
    do {
        let receipt = try BuildReceipt.validated(plan: plan, result: .apparatusFailed(apparatus))
        Issue.record("failed build yielded a receipt")
        #expect(receipt.artifactDigest == digest)
    } catch let error {
        #expect(error == .buildFailed(apparatus))
    }
    do {
        let receipt = try BaselineReceipt.validated(
            plan: plan,
            discovery: discovery,
            results: [],
            transcriptDigest: digest
        )
        Issue.record("empty baseline yielded a receipt")
        #expect(receipt.transcriptDigest == digest)
    } catch let error {
        #expect(error == .planMismatch(.tests))
    }
    do {
        let receipt = try ExecutionReceipt.validated(
            plan: plan,
            results: [.world(evidence.worlds[0])],
            transcriptDigest: digest,
            executionCount: evidence.executionCount
        )
        Issue.record("missing mutant execution yielded a receipt")
        #expect(receipt.transcriptDigest == digest)
    } catch let error {
        #expect(error == .planMismatch(.mutants))
    }
}

@Test
func auditRequiresEveryMutantWorldPairExactlyOnce() throws {
    let mutant = try MutantID.parse("mutant-1")
    let unknownMutant = try MutantID.parse("mutant-unknown")
    let firstWorld = try WorldID.parse("world-1")
    let secondWorld = try WorldID.parse("world-2")
    let unknownWorld = try WorldID.parse("world-unknown")
    let first = passedMutation(mutant: mutant, world: firstWorld)
    let second = passedMutation(mutant: mutant, world: secondWorld)
    #expect(throws: AuditError.missingMutationObservation(mutant, secondWorld)) {
        try AuditKernel.close(twoWorldCatalog(mutationObservations: [first]))
    }
    #expect(throws: AuditError.duplicateMutationObservation(mutant, firstWorld)) {
        try AuditKernel.close(twoWorldCatalog(mutationObservations: [first, first, second]))
    }
    #expect(throws: AuditError.unknownMutationObservation(mutant, unknownWorld)) {
        try AuditKernel.close(twoWorldCatalog(mutationObservations: [first, second,
            passedMutation(mutant: mutant, world: unknownWorld)]))
    }
    #expect(throws: AuditError.unknownMutationObservation(unknownMutant, firstWorld)) {
        try AuditKernel.close(twoWorldCatalog(mutationObservations: [first, second,
            passedMutation(mutant: unknownMutant, world: firstWorld)]))
    }
    let closed = try AuditKernel.close(twoWorldCatalog(mutationObservations: [first, second]))
    #expect(closed.evidence.mutationObservations.count == 2)
    #expect(closed.verdict == .gaps)
}

@Test
func executionReceiptRequiresEveryMutantWorldPairExactlyOnce() throws {
    let mutant = try MutantID.parse("mutant-1")
    let firstWorld = try WorldID.parse("world-1")
    let secondWorld = try WorldID.parse("world-2")
    let unknownWorld = try WorldID.parse("world-unknown")
    let catalog = try twoWorldCatalog(mutationObservations: [
        passedMutation(mutant: mutant, world: firstWorld),
        passedMutation(mutant: mutant, world: secondWorld),
    ])
    let digest = try Digest.sha256(Data("mutant-world-closure".utf8))
    let plan = FrozenPlan(run: catalog.run, worlds: catalog.worlds, mutants: catalog.mutants, digest: digest)
    let complete = plannedExecutionResults(for: plan)
    #expect(throws: PipelineError.planMismatch(.mutants)) {
        try ExecutionReceipt.validated(
            plan: plan,
            results: Array(complete.dropLast()),
            transcriptDigest: digest,
            executionCount: catalog.executionCount
        )
    }
    #expect(throws: PipelineError.planMismatch(.mutants)) {
        try ExecutionReceipt.validated(
            plan: plan,
            results: complete + [.mutant(mutant, firstWorld)],
            transcriptDigest: digest,
            executionCount: catalog.executionCount
        )
    }
    #expect(throws: PipelineError.planMismatch(.mutants)) {
        try ExecutionReceipt.validated(
            plan: plan,
            results: complete + [.mutant(mutant, unknownWorld)],
            transcriptDigest: digest,
            executionCount: catalog.executionCount
        )
    }
    let receipt = try ExecutionReceipt.validated(
        plan: plan,
        results: complete,
        transcriptDigest: digest,
        executionCount: catalog.executionCount
    )
    #expect(receipt.transcriptDigest == digest)
}

@Test
func pipelineReceiptBindsTheWholePlanNotOnlyItsDigest() throws {
    let evidence = try catalog(failures: [])
    let digest = try Digest.sha256(Data("same-digest".utf8))
    let plan = FrozenPlan(
        run: evidence.run,
        worlds: evidence.worlds,
        mutants: evidence.mutants,
        digest: digest
    )
    let changedPlan = FrozenPlan(
        run: try RunID.parse("changed-run"),
        worlds: evidence.worlds,
        mutants: evidence.mutants,
        digest: digest
    )
    let receipt = try BuildReceipt.validated(plan: plan, result: .completed(artifactDigest: digest))
    let discovery = DiscoveryCatalog(
        preservationClaims: evidence.preservationClaims,
        detectionClaims: evidence.detectionClaims,
        tests: [try TestID.parse("test-1")]
    )
    let frozen = try Pipeline<Discovered>.discover(discovery).plan().freeze(changedPlan)
    do {
        let built = try frozen.built(receipt: receipt)
        Issue.record("receipt for another plan was accepted")
        let baselineReceipt = try BaselineReceipt.validated(
            plan: changedPlan,
            discovery: discovery,
            results: [.passed(discovery.tests[0])],
            transcriptDigest: digest
        )
        let baseline = try built.baselinePassed(receipt: baselineReceipt)
        let executionReceipt = try ExecutionReceipt.validated(
            plan: changedPlan,
            results: plannedExecutionResults(for: changedPlan),
            transcriptDigest: digest,
            executionCount: evidence.executionCount
        )
        let executed = try baseline.executed(receipt: executionReceipt)
        let recorded = executed.record(evidence)
        let audited = try recorded.audit()
        let closed = try audited.closedCatalog()
        #expect(closed.verdict == .invalid)
    } catch let error {
        #expect(error == .planMismatch(.receipt))
    }
}

@Test
func recordedExecutionCountMustMatchTheExecutionReceipt() throws {
    let evidence = try catalog(failures: [])
    let discovery = DiscoveryCatalog(
        preservationClaims: evidence.preservationClaims,
        detectionClaims: evidence.detectionClaims,
        tests: [try TestID.parse("test-1")]
    )
    let plan = FrozenPlan(
        run: evidence.run,
        worlds: evidence.worlds,
        mutants: evidence.mutants,
        digest: try Digest.sha256(Data("plan-count".utf8))
    )
    let receipts = try structuralReceipts(
        plan: plan,
        discovery: discovery,
        executionCount: .nonnegative(2)
    )
    let discovered = Pipeline<Discovered>.discover(discovery)
    let planned = try discovered.plan()
    let frozen = planned.freeze(plan)
    let built = try frozen.built(receipt: receipts.build)
    let baseline = try built.baselinePassed(receipt: receipts.baseline)
    let executed = try baseline.executed(receipt: receipts.execution)
    let recorded = executed.record(evidence)
    do {
        let audited = try recorded.audit()
        let closed = try audited.closedCatalog()
        Issue.record("execution count drift was accepted")
        #expect(closed.verdict == .invalid)
    } catch let error {
        #expect(error == .planMismatch(.executionCount))
    }
}

private func structuralReceipts(
    plan: FrozenPlan,
    discovery: DiscoveryCatalog,
    executionCount: EvidenceCount
) throws -> (build: BuildReceipt, baseline: BaselineReceipt, execution: ExecutionReceipt) {
    let digest = try Digest.sha256(Data("structural-fixture-not-runtime-proof".utf8))
    let build = try BuildReceipt.validated(plan: plan, result: .completed(artifactDigest: digest))
    let baseline = try BaselineReceipt.validated(
        plan: plan,
        discovery: discovery,
        results: discovery.tests.map { BaselineTestResult.passed($0) },
        transcriptDigest: digest
    )
    let observations = plannedExecutionResults(for: plan)
    let execution = try ExecutionReceipt.validated(
        plan: plan,
        results: observations,
        transcriptDigest: digest,
        executionCount: executionCount
    )
    return (build, baseline, execution)
}

private func plannedExecutionResults(for plan: FrozenPlan) -> [PlannedExecutionResult] {
    plan.worlds.map { PlannedExecutionResult.world($0) }
        + plan.mutants.flatMap { mutant in
            plan.worlds.map { world in PlannedExecutionResult.mutant(mutant, world) }
        }
}

private func passedMutation(mutant: MutantID, world: WorldID) -> MutationObservation {
    MutationObservation(mutant: mutant, world: world, reached: .passed, infected: .passed, detected: .passed)
}

private func modeledWorld(id: WorldID, locale: LocaleScenario) throws -> DeclaredWorld {
    let world = World(
        id: id,
        build: .debug,
        operatingSystem: .iOS,
        device: DeviceProfile(id: try DeviceID.parse("device-1"), family: .phone),
        locale: locale,
        layoutDirection: .leftToRight,
        appearance: .light,
        accessibility: .standard,
        permission: PermissionScenario(kind: .camera, state: .granted),
        location: .fixed,
        biometrics: .succeeds,
        lifecycle: .foreground,
        data: .typical,
        serviceFault: .none,
        cancellation: .never,
        schedule: ScheduleScenario(id: try ScheduleID.parse("schedule-1"), decisions: []),
        mutant: .clean
    )
    return .modeled(WorldDefinition(world: world))
}

private func twoWorldCatalog(mutationObservations: [MutationObservation]) throws -> EvidenceCatalog {
    let base = try catalog(failures: [])
    let worlds = [try WorldID.parse("world-1"), try WorldID.parse("world-2")]
    let claimIDs = Array(base.preservationClaims) + Array(base.detectionClaims)
    let observations = claimIDs.flatMap { claim in
        worlds.map { world in
            ClaimObservation(claim: claim, world: world, status: .passed, diagnostic: nil)
        }
    }
    return EvidenceCatalog(
        run: base.run,
        scope: base.scope,
        inputContinuity: base.inputContinuity,
        runtimePipeline: base.runtimePipeline,
        preservationClaims: base.preservationClaims,
        detectionClaims: base.detectionClaims,
        worlds: .unmodeledHosts(worlds),
        mutants: base.mutants,
        claimObservations: observations,
        mutationObservations: mutationObservations,
        lawObservations: base.lawObservations,
        schemaObservations: base.schemaObservations,
        failures: base.failures,
        review: base.review,
        executionCount: base.executionCount
    )
}

private func catalog(
    failures: [ExecutionFailure],
    lawObservations: [LawObservation] = LawCode.allCases.map { LawObservation(code: $0, status: .passed) }
) throws -> EvidenceCatalog {
    let preservation = try ClaimID.parse("preservation-1")
    let detection = try ClaimID.parse("detection-1")
    let world = try WorldID.parse("world-1")
    let mutant = try MutantID.parse("mutant-1")
    return EvidenceCatalog(
        run: try RunID.parse("run-model"),
        scope: .complete,
        inputContinuity: .eventFree,
        runtimePipeline: .unverified,
        preservationClaims: .from([try Claim<Preservation>.preservation(
            id: preservation,
            name: "preservation"
        )]),
        detectionClaims: .from([try Claim<Detection>.detection(
            id: detection,
            name: "detection"
        )]),
        worlds: .unmodeledHosts([world]),
        mutants: [mutant],
        claimObservations: [
            ClaimObservation(claim: preservation, world: world, status: .passed, diagnostic: nil),
            ClaimObservation(claim: detection, world: world, status: .passed, diagnostic: nil),
        ],
        mutationObservations: [MutationObservation(
            mutant: mutant,
            world: world,
            reached: .passed,
            infected: .passed,
            detected: .passed
        )],
        lawObservations: lawObservations,
        schemaObservations: [SchemaObservation(version: .v2, status: .passed)],
        failures: failures,
        review: IndependentReview(
            status: .accepted,
            evidence: try Digest.sha256(Data("review".utf8))
        ),
        executionCount: try EvidenceCount.nonnegative(1)
    )
}
