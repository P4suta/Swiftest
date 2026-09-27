import SwiftestModel

public struct WorldCaseKey: Hashable, Sendable {
    public let world: WorldID
    public let mutant: MutantSelection

    private init(world: WorldID, mutant: MutantSelection) {
        self.world = world
        self.mutant = mutant
    }

    public static func planned(_ world: World) -> WorldCaseKey {
        WorldCaseKey(world: world.id, mutant: world.mutant)
    }
}

public enum WorldCaseAccountingError: Error, Equatable, Sendable {
    case count(NumericValueError)
    case planCardinality(expected: EvidenceCount, actual: EvidenceCount)
    case duplicatePlan(WorldCaseKey)
    case missing(WorldCaseKey)
    case duplicate(WorldCaseKey)
    case unexpected(WorldCaseKey)
    case mismatchedWorld(WorldCaseKey)
    case mismatchedTest(SwiftTestingTestID)
    case mismatchedClaim(ClaimID)
    case unsupportedIrrelevance(WorldCaseKey)
}

public struct UnboundAggregateWorldCases: Equatable, Sendable {
    public let plannedWorldCases: EvidenceCount
    public let tests: TargetTestObservation

    fileprivate init(plannedWorldCases: EvidenceCount, tests: TargetTestObservation) {
        self.plannedWorldCases = plannedWorldCases
        self.tests = tests
    }
}

public struct UnverifiedIndividualWorldCase<Polarity>: Sendable {
    public let world: World
    public let test: SwiftTestingTestID
    public let claim: Claim<Polarity>
    public let status: ObservationStatus

    package init(
        world: World,
        test: SwiftTestingTestID,
        claim: Claim<Polarity>,
        status: ObservationStatus
    ) {
        self.world = world
        self.test = test
        self.claim = claim
        self.status = status
    }
}

public struct StructurallyMatchedWorldCases<Polarity>: Sendable {
    public let count: EvidenceCount
    public let individuals: [UnverifiedIndividualWorldCase<Polarity>]

    private init(count: EvidenceCount, individuals: [UnverifiedIndividualWorldCase<Polarity>]) {
        self.count = count
        self.individuals = individuals
    }

    fileprivate static func matched(
        count: EvidenceCount,
        individuals: [UnverifiedIndividualWorldCase<Polarity>]
    ) -> StructurallyMatchedWorldCases<Polarity> {
        StructurallyMatchedWorldCases(count: count, individuals: individuals)
    }
}

public struct WorldCasePlan<Polarity>: Sendable {
    public let claim: Claim<Polarity>
    public let test: SwiftTestingTestID
    private let cases: [WorldCaseKey: World]
    private let order: [WorldCaseKey]
    private let expectedCount: EvidenceCount

    public init(
        worlds: WorldSequence,
        test: SwiftTestingTestID,
        claim: Claim<Polarity>
    ) throws(WorldCaseAccountingError) {
        var cases: [WorldCaseKey: World] = [:]
        var order: [WorldCaseKey] = []
        for world in worlds {
            let key = WorldCaseKey.planned(world)
            if cases.updateValue(world, forKey: key) != nil {
                throw .duplicatePlan(key)
            }
            order.append(key)
        }
        let actualCount: EvidenceCount
        do {
            actualCount = try .nonnegative(order.count)
        } catch let error {
            throw .count(error)
        }
        if actualCount != worlds.executionCount {
            throw .planCardinality(expected: worlds.executionCount, actual: actualCount)
        }
        self.claim = claim
        self.test = test
        self.cases = cases
        self.order = order
        self.expectedCount = worlds.executionCount
    }

    public var count: Int { order.count }

    public func account(
        aggregate: TargetTestObservation
    ) -> UnboundAggregateWorldCases {
        UnboundAggregateWorldCases(plannedWorldCases: expectedCount, tests: aggregate)
    }

    package func account(
        individuals: [UnverifiedIndividualWorldCase<Polarity>]
    ) throws(WorldCaseAccountingError) -> StructurallyMatchedWorldCases<Polarity> {
        var observed: [WorldCaseKey: UnverifiedIndividualWorldCase<Polarity>] = [:]
        for individual in individuals {
            let key = WorldCaseKey.planned(individual.world)
            guard let planned = cases[key] else {
                throw .unexpected(key)
            }
            if planned != individual.world {
                throw .mismatchedWorld(key)
            }
            if individual.test != test {
                throw .mismatchedTest(individual.test)
            }
            if individual.claim != claim {
                throw .mismatchedClaim(individual.claim.id)
            }
            if individual.status == .provenIrrelevant {
                throw .unsupportedIrrelevance(key)
            }
            if observed.updateValue(individual, forKey: key) != nil {
                throw .duplicate(key)
            }
        }
        var ordered: [UnverifiedIndividualWorldCase<Polarity>] = []
        ordered.reserveCapacity(order.count)
        for key in order {
            guard let individual = observed[key] else {
                throw .missing(key)
            }
            ordered.append(individual)
        }
        return .matched(count: expectedCount, individuals: ordered)
    }
}
