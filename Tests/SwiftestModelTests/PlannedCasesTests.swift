import SwiftestModel
import Testing

@Test
func campaignDeclarationEnumeratesCanonicalTypedObligations() throws {
    let firstTest = try TestID.parse("test-a")
    let secondTest = try TestID.parse("test-b")
    let firstClaim = try Claim<Preservation>.preservation(id: ClaimID.parse("claim-a"), name: "preserve")
    let secondClaim = try Claim<Detection>.detection(id: ClaimID.parse("claim-b"), name: "detect")
    let mutant = try MutantID.parse("mutant-a")
    let firstWorld = try WorldID.parse("world-a")
    let secondWorld = try WorldID.parse("world-b")
    let worlds = try [
        plannedWorld(id: secondWorld, mutant: .mutant(mutant)),
        plannedWorld(id: firstWorld, mutant: .clean),
        plannedWorld(id: secondWorld, mutant: .clean),
        plannedWorld(id: firstWorld, mutant: .mutant(mutant)),
    ]
    let preservation = ClaimTestBinding<Preservation>.bind(test: secondTest, claim: firstClaim)
    let detection = ClaimTestBinding<Detection>.bind(test: firstTest, claim: secondClaim)
    let declared = try CampaignDeclaration.declare(
        preservation: [preservation],
        detection: [detection],
        worlds: worlds
    )
    let permuted = try CampaignDeclaration.declare(
        preservation: [preservation],
        detection: [detection],
        worlds: Array(worlds.reversed())
    )
    #expect(declared == permuted)
    #expect(declared.discovery.tests == [firstTest, secondTest])
    #expect(Array(declared.discovery.preservationClaims) == [firstClaim.id])
    #expect(Array(declared.discovery.detectionClaims) == [secondClaim.id])
    #expect(Array(declared.declaredWorlds) == [firstWorld, secondWorld])
    #expect(declared.mutants == [mutant])
    #expect(declared.obligations.count == 8)
    #expect(Set(declared.obligations).count == 8)
    #expect(declared.obligations.first == .preservation(
        .planned(test: secondTest, claim: firstClaim, world: worlds[1])
    ))
    #expect(declared.obligations.last == .detection(
        .planned(test: firstTest, claim: secondClaim, world: worlds[0])
    ))
    let required = PlannedWorldCaseID.required(worlds: declared.declaredWorlds, mutants: declared.mutants)
    #expect(required == declared.worlds.map(PlannedWorldCaseID.planned))
}

@Test
func plannedCaseIdentitySeparatesEveryAxisAndPolarity() throws {
    let worldID = try WorldID.parse("world-a")
    let otherWorldID = try WorldID.parse("world-b")
    let mutant = try MutantID.parse("mutant-a")
    let cleanWorld = try plannedWorld(id: worldID, mutant: .clean)
    let mutantWorld = try plannedWorld(id: worldID, mutant: .mutant(mutant))
    let otherWorld = try plannedWorld(id: otherWorldID, mutant: .clean)
    let test = try TestID.parse("test-a")
    let otherTest = try TestID.parse("test-b")
    let claim = try Claim<Preservation>.preservation(id: ClaimID.parse("claim-a"), name: "first")
    let otherClaim = try Claim<Preservation>.preservation(id: ClaimID.parse("claim-b"), name: "second")
    let keys: Set<PlannedClaimCaseID<Preservation>> = [
        .planned(test: test, claim: claim, world: cleanWorld),
        .planned(test: otherTest, claim: claim, world: cleanWorld),
        .planned(test: test, claim: otherClaim, world: cleanWorld),
        .planned(test: test, claim: claim, world: mutantWorld),
        .planned(test: test, claim: claim, world: otherWorld),
    ]
    #expect(keys.count == 5)
    #expect(PlannedWorldCaseID.planned(cleanWorld) != PlannedWorldCaseID.planned(mutantWorld))
    #expect(PlannedWorldCaseID.planned(cleanWorld) != PlannedWorldCaseID.planned(otherWorld))
}

@Test
func campaignDeclarationRejectsDuplicateAndConflictingBindings() throws {
    let test = try TestID.parse("test-a")
    let claimID = try ClaimID.parse("claim-a")
    let preservation = try Claim<Preservation>.preservation(id: claimID, name: "first")
    let renamed = try Claim<Preservation>.preservation(id: claimID, name: "other")
    let detection = try Claim<Detection>.detection(id: claimID, name: "first")
    let world = try plannedWorld(id: WorldID.parse("world-a"), mutant: .clean)
    let first = ClaimTestBinding<Preservation>.bind(test: test, claim: preservation)
    let conflicting = ClaimTestBinding<Preservation>.bind(test: try TestID.parse("test-b"), claim: renamed)
    let opposite = ClaimTestBinding<Detection>.bind(test: test, claim: detection)
    #expect(throws: CampaignDeclarationError.duplicateBinding(test, claimID)) {
        try CampaignDeclaration.declare(preservation: [first, first], detection: [], worlds: [world])
    }
    #expect(throws: CampaignDeclarationError.conflictingClaim(claimID)) {
        try CampaignDeclaration.declare(preservation: [first, conflicting], detection: [], worlds: [world])
    }
    #expect(throws: CampaignDeclarationError.polarityCollision(claimID)) {
        try CampaignDeclaration.declare(preservation: [first], detection: [opposite], worlds: [world])
    }
}

@Test
func campaignDeclarationRejectsIncompleteOrAliasedWorldMatrix() throws {
    let test = try TestID.parse("test-a")
    let claim = try Claim<Preservation>.preservation(id: ClaimID.parse("claim-a"), name: "preserve")
    let binding = ClaimTestBinding<Preservation>.bind(test: test, claim: claim)
    let firstID = try WorldID.parse("world-a")
    let secondID = try WorldID.parse("world-b")
    let mutant = try MutantID.parse("mutant-a")
    let firstClean = try plannedWorld(id: firstID, mutant: .clean)
    let firstMutant = try plannedWorld(id: firstID, mutant: .mutant(mutant))
    let secondClean = try plannedWorld(id: secondID, mutant: .clean)
    #expect(throws: CampaignDeclarationError.emptyWorlds) {
        try CampaignDeclaration.declare(preservation: [binding], detection: [], worlds: [])
    }
    #expect(throws: CampaignDeclarationError.duplicateWorldCase(.planned(firstClean))) {
        try CampaignDeclaration.declare(preservation: [binding], detection: [], worlds: [firstClean, firstClean])
    }
    #expect(throws: CampaignDeclarationError.missingWorldCase(.planned(world: secondID, mutant: .mutant(mutant)))) {
        try CampaignDeclaration.declare(
            preservation: [binding], detection: [], worlds: [firstClean, firstMutant, secondClean]
        )
    }
    #expect(throws: CampaignDeclarationError.missingWorldCase(.planned(world: firstID, mutant: .clean))) {
        try CampaignDeclaration.declare(preservation: [binding], detection: [], worlds: [firstMutant])
    }
    let conflicting = try plannedWorld(id: firstID, mutant: .mutant(mutant), locale: .japaneseJapan)
    #expect(throws: CampaignDeclarationError.conflictingWorldDefinition(firstID)) {
        try CampaignDeclaration.declare(preservation: [binding], detection: [], worlds: [firstClean, conflicting])
    }
}

@Test
func executionReceiptUsesTheCanonicalWorldMutantMatrix() throws {
    let firstWorld = try WorldID.parse("world-a")
    let secondWorld = try WorldID.parse("world-b")
    let firstMutant = try MutantID.parse("mutant-a")
    let secondMutant = try MutantID.parse("mutant-b")
    let worlds = DeclaredWorlds.unmodeledHosts([secondWorld, firstWorld])
    let mutants = [secondMutant, firstMutant]
    let required = PlannedWorldCaseID.required(worlds: worlds, mutants: mutants)
    let independent = [firstWorld, secondWorld].flatMap { world in
        [
            PlannedWorldCaseID.planned(world: world, mutant: .clean),
            PlannedWorldCaseID.planned(world: world, mutant: .mutant(firstMutant)),
            PlannedWorldCaseID.planned(world: world, mutant: .mutant(secondMutant)),
        ]
    }
    #expect(required == independent)
    let results: [PlannedExecutionResult] = required.map { planned in
        switch planned.mutant {
        case .clean: .world(planned.world)
        case .mutant(let mutant): .mutant(mutant, planned.world)
        }
    }
    let digest = try Digest.parse(String(repeating: "0", count: 64))
    let plan = FrozenPlan(run: try RunID.parse("run-a"), worlds: worlds, mutants: mutants, digest: digest)
    let receipt = try ExecutionReceipt.validated(
        plan: plan,
        results: Array(results.reversed()),
        transcriptDigest: digest,
        executionCount: .nonnegative(required.count)
    )
    #expect(receipt.executionCount.rawValue == required.count)
    #expect(throws: PipelineError.planMismatch(.mutants)) {
        try ExecutionReceipt.validated(
            plan: plan,
            results: Array(results.dropLast()),
            transcriptDigest: digest,
            executionCount: .nonnegative(required.count)
        )
    }
    #expect(throws: PipelineError.planMismatch(.worlds)) {
        try ExecutionReceipt.validated(
            plan: plan,
            results: Array(results.dropFirst()),
            transcriptDigest: digest,
            executionCount: .nonnegative(required.count)
        )
    }
}

private func plannedWorld(
    id: WorldID,
    mutant: MutantSelection,
    locale: LocaleScenario = .englishUnitedStates
) throws -> World {
    World(
        id: id,
        build: .debug,
        operatingSystem: .iOS,
        device: DeviceProfile(id: try DeviceID.parse("device-a"), family: .phone),
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
        schedule: ScheduleScenario(id: try ScheduleID.parse("schedule-a"), decisions: []),
        mutant: mutant
    )
}
