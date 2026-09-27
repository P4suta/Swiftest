import Foundation
import SwiftestEngine
import SwiftestModel
import Testing

@Test func worldCaseAggregateCannotBeAttributedToPlannedWorlds() throws {
    let fixture = try worldCaseFixture()
    let digest = try Digest.sha256(Data("aggregate".utf8))
    let count = try EvidenceCount.nonnegative(2)

    let unbound = fixture.plan.account(aggregate: .passed(count, digest))
    #expect(unbound.plannedWorldCases == count)
    #expect(unbound.tests == .passed(count, digest))
}

@Test func worldCaseAccountingRejectsMissingIndividual() throws {
    let fixture = try worldCaseFixture()
    let first = try #require(fixture.worlds.first)

    #expect(throws: WorldCaseAccountingError.missing(WorldCaseKey.planned(fixture.worlds[1]))) {
        try fixture.plan.account(individuals: [fixture.individual(first)])
    }
}

@Test func worldCaseAccountingRejectsDuplicateIndividual() throws {
    let fixture = try worldCaseFixture()
    let first = try #require(fixture.worlds.first)

    #expect(throws: WorldCaseAccountingError.duplicate(WorldCaseKey.planned(first))) {
        try fixture.plan.account(individuals: [
            fixture.individual(first),
            fixture.individual(first),
        ])
    }
}

@Test func worldCaseAccountingRejectsMismatchedWorldCoordinates() throws {
    let fixture = try worldCaseFixture()
    let first = try #require(fixture.worlds.first)
    let second = fixture.worlds[1]
    let inconsistent = World(
        id: first.id,
        build: first.build,
        operatingSystem: first.operatingSystem,
        device: first.device,
        locale: second.locale,
        layoutDirection: first.layoutDirection,
        appearance: first.appearance,
        accessibility: first.accessibility,
        permission: first.permission,
        location: first.location,
        biometrics: first.biometrics,
        lifecycle: first.lifecycle,
        data: first.data,
        serviceFault: first.serviceFault,
        cancellation: first.cancellation,
        schedule: first.schedule,
        mutant: first.mutant
    )

    #expect(throws: WorldCaseAccountingError.mismatchedWorld(WorldCaseKey.planned(first))) {
        try fixture.plan.account(individuals: [fixture.individual(inconsistent)])
    }
}

@Test func worldCaseAccountingRejectsUnexpectedWorldAndMismatchedClaim() throws {
    let fixture = try worldCaseFixture()
    let unexpected = try worldCaseFixture(locales: [.germanGermany]).worlds[0]
    let first = try #require(fixture.worlds.first)
    let otherClaim = try Claim<Preservation>.preservation(id: ClaimID.parse("other-claim"), name: "Other claim")

    #expect(throws: WorldCaseAccountingError.unexpected(WorldCaseKey.planned(unexpected))) {
        try fixture.plan.account(individuals: [fixture.individual(unexpected)])
    }
    #expect(throws: WorldCaseAccountingError.mismatchedClaim(otherClaim.id)) {
        try fixture.plan.account(individuals: [UnverifiedIndividualWorldCase(
            world: first,
            test: fixture.test,
            claim: otherClaim,
            status: .passed
        )])
    }
}

@Test func worldCaseAccountingRejectsDuplicatePlannedIdentity() throws {
    let sequence = try worldCaseSpace(locales: [.japaneseJapan], mutants: [.clean, .clean]).allWorlds()
    let first = try #require(Array(sequence).first)
    let test = try SwiftTestingTestID.parse("WorldCaseTests/verify()")
    let claim = try Claim<Preservation>.preservation(id: ClaimID.parse("world-case-claim"), name: "World case claim")

    #expect(throws: WorldCaseAccountingError.duplicatePlan(WorldCaseKey.planned(first))) {
        try WorldCasePlan(worlds: sequence, test: test, claim: claim)
    }
}

@Test func worldCaseAccountingCanOnlyEstablishStructuralCompleteness() throws {
    let fixture = try worldCaseFixture()
    let first = try #require(fixture.worlds.first)
    let second = fixture.worlds[1]
    let accounting = try fixture.plan.account(individuals: [
        fixture.individual(second),
        UnverifiedIndividualWorldCase(world: first, test: fixture.test, claim: fixture.claim, status: .failed),
    ])
    #expect(accounting.count.rawValue == 2)
    #expect(accounting.individuals.map(\.world.id) == fixture.worlds.map(\.id))
    #expect(accounting.individuals.map(\.status) == [.failed, .passed])
}

@Test func worldCaseAccountingRejectsTestAndUnsupportedIrrelevance() throws {
    let fixture = try worldCaseFixture()
    let first = try #require(fixture.worlds.first)
    let otherTest = try SwiftTestingTestID.parse("OtherTests/verify()")

    #expect(throws: WorldCaseAccountingError.mismatchedTest(otherTest)) {
        try fixture.plan.account(individuals: [UnverifiedIndividualWorldCase(
            world: first,
            test: otherTest,
            claim: fixture.claim,
            status: .passed
        )])
    }
    #expect(throws: WorldCaseAccountingError.unsupportedIrrelevance(WorldCaseKey.planned(first))) {
        try fixture.plan.account(individuals: [UnverifiedIndividualWorldCase(
            world: first,
            test: fixture.test,
            claim: fixture.claim,
            status: .provenIrrelevant
        )])
    }
}

private struct WorldCaseFixture {
    let worlds: [World]
    let plan: WorldCasePlan<Preservation>
    let test: SwiftTestingTestID
    let claim: Claim<Preservation>

    func individual(_ world: World) -> UnverifiedIndividualWorldCase<Preservation> {
        UnverifiedIndividualWorldCase(world: world, test: test, claim: claim, status: .passed)
    }
}

private func worldCaseFixture(
    locales: [LocaleScenario] = [.englishUnitedStates, .japaneseJapan]
) throws -> WorldCaseFixture {
    let test = try SwiftTestingTestID.parse("WorldCaseTests/verify()")
    let claim = try Claim<Preservation>.preservation(id: ClaimID.parse("world-case-claim"), name: "World case claim")
    let sequence = try worldCaseSpace(locales: locales).allWorlds()
    return try WorldCaseFixture(
        worlds: Array(sequence),
        plan: WorldCasePlan(worlds: sequence, test: test, claim: claim),
        test: test,
        claim: claim
    )
}

private func worldCaseSpace(
    locales: [LocaleScenario],
    mutants: [MutantSelection] = [.clean]
) throws -> WorldSpace {
    WorldSpace(
        builds: .enumerated([.debug]),
        operatingSystems: .enumerated([.macOS]),
        devices: .enumerated([DeviceProfile(id: try DeviceID.parse("world-case-device"), family: .mac)]),
        locales: .enumerated(locales),
        layoutDirections: .enumerated([.leftToRight]),
        appearances: .enumerated([.light]),
        accessibilityScenarios: .enumerated([.standard]),
        permissions: .enumerated([PermissionScenario(kind: .camera, state: .granted)]),
        locations: .enumerated([.fixed]),
        biometrics: .enumerated([.succeeds]),
        lifecycles: .enumerated([.foreground]),
        dataScenarios: .enumerated([.typical]),
        serviceFaults: .enumerated([.none]),
        cancellations: .enumerated([.never]),
        schedules: .enumerated([ScheduleScenario(id: try ScheduleID.parse("world-case-schedule"), decisions: [])]),
        mutants: .enumerated(mutants)
    )
}
