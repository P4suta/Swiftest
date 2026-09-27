public struct PlannedWorldCaseID: Hashable, Sendable {
    public let world: WorldID
    public let mutant: MutantSelection

    private init(world: WorldID, mutant: MutantSelection) {
        self.world = world
        self.mutant = mutant
    }

    public static func planned(_ world: World) -> Self {
        Self(world: world.id, mutant: world.mutant)
    }

    public static func planned(world: WorldID, mutant: MutantSelection) -> Self {
        Self(world: world, mutant: mutant)
    }

    package static func required(worlds: DeclaredWorlds, mutants: [MutantID]) -> [Self] {
        let orderedWorlds = Array(worlds).sorted { $0.rawValue < $1.rawValue }
        let orderedMutants = mutants.sorted { $0.rawValue < $1.rawValue }
        return orderedWorlds.flatMap { world in
            [Self(world: world, mutant: .clean)]
                + orderedMutants.map { Self(world: world, mutant: .mutant($0)) }
        }
    }
}

public struct PlannedClaimCaseID<Polarity>: Hashable, Sendable {
    public let test: TestID
    public let claim: ClaimID
    public let worldCase: PlannedWorldCaseID

    private init(test: TestID, claim: ClaimID, worldCase: PlannedWorldCaseID) {
        self.test = test
        self.claim = claim
        self.worldCase = worldCase
    }

    public static func planned(test: TestID, claim: Claim<Polarity>, world: World) -> Self {
        Self(test: test, claim: claim.id, worldCase: .planned(world))
    }
}

public struct ClaimTestBinding<Polarity>: Hashable, Sendable {
    public let test: TestID
    public let claim: Claim<Polarity>

    private init(test: TestID, claim: Claim<Polarity>) {
        self.test = test
        self.claim = claim
    }

    public static func bind(test: TestID, claim: Claim<Polarity>) -> Self {
        Self(test: test, claim: claim)
    }
}

public enum PlannedCaseObligation: Hashable, Sendable {
    case preservation(PlannedClaimCaseID<Preservation>)
    case detection(PlannedClaimCaseID<Detection>)
}

public enum CampaignDeclarationError: Error, Equatable, Sendable {
    case emptyBindings
    case emptyWorlds
    case duplicateBinding(TestID, ClaimID)
    case conflictingClaim(ClaimID)
    case polarityCollision(ClaimID)
    case duplicateWorldCase(PlannedWorldCaseID)
    case conflictingWorldDefinition(WorldID)
    case impossibleWorld(WorldID)
    case missingWorldCase(PlannedWorldCaseID)
}

public struct CampaignDeclaration: Equatable, Sendable {
    public let preservationBindings: [ClaimTestBinding<Preservation>]
    public let detectionBindings: [ClaimTestBinding<Detection>]
    public let worlds: [World]
    public let discovery: DiscoveryCatalog
    public let declaredWorlds: DeclaredWorlds
    public let mutants: [MutantID]
    public let obligations: [PlannedCaseObligation]

    private init(
        preservationBindings: [ClaimTestBinding<Preservation>],
        detectionBindings: [ClaimTestBinding<Detection>],
        worlds: [World],
        discovery: DiscoveryCatalog,
        declaredWorlds: DeclaredWorlds,
        mutants: [MutantID],
        obligations: [PlannedCaseObligation]
    ) {
        self.preservationBindings = preservationBindings
        self.detectionBindings = detectionBindings
        self.worlds = worlds
        self.discovery = discovery
        self.declaredWorlds = declaredWorlds
        self.mutants = mutants
        self.obligations = obligations
    }

    public static func declare(
        preservation: [ClaimTestBinding<Preservation>],
        detection: [ClaimTestBinding<Detection>],
        worlds: [World]
    ) throws(CampaignDeclarationError) -> Self {
        guard !preservation.isEmpty || !detection.isEmpty else {
            throw .emptyBindings
        }
        guard !worlds.isEmpty else {
            throw .emptyWorlds
        }
        var claimDefinitions: [ClaimID: DeclaredClaimIdentity] = [:]
        var preservationClaims: [ClaimID: Claim<Preservation>] = [:]
        var detectionClaims: [ClaimID: Claim<Detection>] = [:]
        var tests = Set<TestID>()
        var seenBindings = Set<BindingPoint>()
        for binding in preservation {
            try validateBinding(
                test: binding.test,
                claim: binding.claim.id,
                name: binding.claim.name,
                polarity: .preservation,
                claims: &claimDefinitions,
                bindings: &seenBindings
            )
            tests.insert(binding.test)
            preservationClaims[binding.claim.id] = binding.claim
        }
        for binding in detection {
            try validateBinding(
                test: binding.test,
                claim: binding.claim.id,
                name: binding.claim.name,
                polarity: .detection,
                claims: &claimDefinitions,
                bindings: &seenBindings
            )
            tests.insert(binding.test)
            detectionClaims[binding.claim.id] = binding.claim
        }

        var definitions: [WorldID: WorldDefinition] = [:]
        var worldCases = Set<PlannedWorldCaseID>()
        var mutantIDs = Set<MutantID>()
        for world in worlds {
            let definition = WorldDefinition(world: world)
            guard definition.isPhysicallyPossible else {
                throw .impossibleWorld(world.id)
            }
            if let previous = definitions[world.id], previous != definition {
                throw .conflictingWorldDefinition(world.id)
            }
            definitions[world.id] = definition
            let worldCase = PlannedWorldCaseID.planned(world)
            guard worldCases.insert(worldCase).inserted else {
                throw .duplicateWorldCase(worldCase)
            }
            if case .mutant(let mutant) = world.mutant {
                mutantIDs.insert(mutant)
            }
        }
        let orderedDefinitions = definitions.values.sorted { $0.id.rawValue < $1.id.rawValue }
        let declaredWorlds = DeclaredWorlds.from(orderedDefinitions.map(DeclaredWorld.modeled))
        let orderedMutants = mutantIDs.sorted { $0.rawValue < $1.rawValue }
        for required in PlannedWorldCaseID.required(worlds: declaredWorlds, mutants: orderedMutants) {
            guard worldCases.contains(required) else {
                throw .missingWorldCase(required)
            }
        }
        let orderedWorlds = worlds.sorted(by: worldLessThan)
        let orderedPreservation = preservation.sorted(by: bindingLessThan)
        let orderedDetection = detection.sorted(by: bindingLessThan)
        let discovery = DiscoveryCatalog(
            preservationClaims: .from(preservationClaims.values.sorted { $0.id.rawValue < $1.id.rawValue }),
            detectionClaims: .from(detectionClaims.values.sorted { $0.id.rawValue < $1.id.rawValue }),
            tests: tests.sorted { $0.rawValue < $1.rawValue }
        )
        let obligations = orderedPreservation.flatMap { binding in
            orderedWorlds.map { world in
                PlannedCaseObligation.preservation(.planned(test: binding.test, claim: binding.claim, world: world))
            }
        } + orderedDetection.flatMap { binding in
            orderedWorlds.map { world in
                PlannedCaseObligation.detection(.planned(test: binding.test, claim: binding.claim, world: world))
            }
        }
        return Self(
            preservationBindings: orderedPreservation,
            detectionBindings: orderedDetection,
            worlds: orderedWorlds,
            discovery: discovery,
            declaredWorlds: declaredWorlds,
            mutants: orderedMutants,
            obligations: obligations
        )
    }
}

private enum BindingPolarity: Hashable {
    case preservation
    case detection
}

private struct DeclaredClaimIdentity {
    let name: String
    let polarity: BindingPolarity
}

private struct BindingPoint: Hashable {
    let test: TestID
    let claim: ClaimID
    let polarity: BindingPolarity
}

private func validateBinding(
    test: TestID,
    claim: ClaimID,
    name: String,
    polarity: BindingPolarity,
    claims: inout [ClaimID: DeclaredClaimIdentity],
    bindings: inout Set<BindingPoint>
) throws(CampaignDeclarationError) {
    if let previous = claims[claim] {
        if previous.polarity != polarity {
            throw .polarityCollision(claim)
        }
        if previous.name != name {
            throw .conflictingClaim(claim)
        }
    }
    let point = BindingPoint(test: test, claim: claim, polarity: polarity)
    guard bindings.insert(point).inserted else {
        throw .duplicateBinding(test, claim)
    }
    claims[claim] = DeclaredClaimIdentity(name: name, polarity: polarity)
}

private func bindingLessThan<Polarity>(
    _ lhs: ClaimTestBinding<Polarity>,
    _ rhs: ClaimTestBinding<Polarity>
) -> Bool {
    if lhs.test != rhs.test {
        return lhs.test.rawValue < rhs.test.rawValue
    }
    return lhs.claim.id.rawValue < rhs.claim.id.rawValue
}

private func worldLessThan(_ lhs: World, _ rhs: World) -> Bool {
    if lhs.id != rhs.id {
        return lhs.id.rawValue < rhs.id.rawValue
    }
    switch (lhs.mutant, rhs.mutant) {
    case (.clean, .mutant):
        return true
    case (.mutant, .clean):
        return false
    case (.clean, .clean):
        return false
    case (.mutant(let first), .mutant(let second)):
        return first.rawValue < second.rawValue
    }
}
