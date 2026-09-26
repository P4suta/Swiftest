import Foundation
import SwiftestEngine
import SwiftestFaults
import SwiftestModel
import SwiftestMutation
import SwiftestScheduler
import SwiftestSolver
import Testing

@Test
func worldSpaceEnumeratesEveryDeclaredCombination() throws {
    let space = try worldSpace()
    let worlds = try space.allWorlds()
    #expect(try space.executionCount().rawValue == 4)
    #expect(worlds.count == 4)
    #expect(Set(worlds.map(\.build)) == [.debug, .release])
    #expect(Set(worlds.map(\.appearance)) == [.light, .dark])
}

@Test
func dporReductionPreservesEveryCanonicalTrace() throws {
    let resource = try ResourceID.parse("independent")
    let first = try ScheduledAction(
        id: "a",
        task: 0,
        accesses: [ResourceAccess(resource: resource, mode: .read)]
    )
    let second = try ScheduledAction(
        id: "b",
        task: 1,
        accesses: []
    )
    let full = try DeterministicScheduler.traces(tasks: [[first], [second]], proofMode: .disabled)
    let reduced = try DeterministicScheduler.traces(tasks: [[first], [second]], proofMode: .enabled)
    #expect(full.count == 2)
    #expect(reduced.count == 1)
    try DPORProofKernel.verify(full: full, reduced: reduced)
}

@Test
func satSolverCertificateIsIndependentlyChecked() throws {
    let first = try SATVariable.make(1)
    let second = try SATVariable.make(2)
    let formula = SATFormula(clauses: [
        try SATClause.make([.positive(first), .positive(second)]),
        try SATClause.make([.negative(first), .positive(second)]),
    ])
    let result = try SATSolver.solve(formula)
    switch result {
    case .satisfiable(let certificate):
        try SATProofKernel.verify(formula: formula, certificate: certificate)
    case .unsatisfiable(let certificate):
        Issue.record("unexpected unsatisfiable certificate")
        #expect(certificate.checkedAssignments.rawValue == 0)
    }
}

@Test
func mutationLexerNeverMutatesStringsOrComments() throws {
    let source = "let text = \"true == false\"\n" + "/" + "/ true == false\nlet value = true\n"
    let candidates = try MutationEngine.discover(in: source)
    #expect(candidates.count == 1)
    #expect(candidates[0].schema == .booleanFlip)
    let mutant = try MutationEngine.apply(candidates[0], to: source)
    #expect(mutant.hasSuffix("let value = false\n"))
}

@Test
func symbolicSilDistinguishesEquivalentAndDifferentMutants() throws {
    let left = "%0 = argument 0\n%1 = integer_literal 1\n%2 = add %0 %1\nreturn %2"
    let reordered = "%0 = argument 0\n%1 = integer_literal 1\n%2 = add %1 %0\nreturn %2"
    let changed = "%0 = argument 0\n%1 = integer_literal 1\n%2 = subtract %0 %1\nreturn %2"
    #expect(try SymbolicSIL.compare(original: left, mutant: reordered) == .identical)
    #expect(try SymbolicSIL.compare(original: left, mutant: changed) == .different)
}

@Test
func standardFaultCampaignCoversEveryDomainAndDeclaredScenario() throws {
    let campaign = try StandardFaultCampaign.make()
    #expect(campaign.points.count == 22)
    #expect(campaign.compounds.count == 6)
    #expect(campaign.scenarios.count == 29)
    #expect(Set(campaign.points.map(\.domain)) == Set(FaultDomain.allCases))
    let observations = StandardFaultCampaign.apparatusObservations(for: campaign)
    let audit = try FaultAuditKernel.close(campaign: campaign, observations: observations)
    #expect(audit.scenarioCount.rawValue == 29)
    #expect(audit.injectedPointCount.rawValue == 34)
}

@Test
func everyUnreachedFaultInvalidatesTheCampaign() throws {
    let campaign = try StandardFaultCampaign.make()
    let passing = StandardFaultCampaign.apparatusObservations(for: campaign)
    for scenario in campaign.scenarios where scenario.kind != .clean {
        guard let point = scenario.activations.first else {
            Issue.record("scenario without activation")
            continue
        }
        let failing = passing.map { observation in
            if observation.scenario != scenario.id {
                return observation
            }
            let activations = scenario.activations.map { activation in
                let result: FaultActivationResult
                if activation.id == point.id {
                    result = .unreached
                } else {
                    result = activation.expectation == .recover ? .recovered : .failedClosed
                }
                return FaultActivationObservation(point: activation.id, result: result)
            }
            return FaultScenarioObservation(scenario: scenario.id, result: .injected(activations))
        }
        do {
            let audit = try FaultAuditKernel.close(campaign: campaign, observations: failing)
            Issue.record("unreached fault accepted")
            #expect(audit.digest.rawValue.isEmpty)
        } catch let error {
            #expect(error == .faultUnreached(scenario.id, point.id))
        }
    }
}

@Test
func faultAuditRejectsMissingUndetectedAndUncontrolledResults() throws {
    let campaign = try StandardFaultCampaign.make()
    let passing = StandardFaultCampaign.apparatusObservations(for: campaign)
    guard let last = passing.last else {
        Issue.record("empty fault observations")
        return
    }
    do {
        let audit = try FaultAuditKernel.close(campaign: campaign, observations: Array(passing.dropLast()))
        Issue.record("missing scenario accepted")
        #expect(audit.digest.rawValue.isEmpty)
    } catch let error {
        #expect(error == .missingScenario(last.scenario))
    }
    guard let single = campaign.scenarios.first(where: { $0.kind == .single }),
        let point = single.activations.first else {
        Issue.record("single fault scenario absent")
        return
    }
    for result in [FaultActivationResult.uncontrolled, .undetectedRecovered] {
        let replaced = passing.map { observation in
            observation.scenario == single.id
                ? FaultScenarioObservation(
                    scenario: single.id,
                    result: .injected([FaultActivationObservation(point: point.id, result: result)])
                )
                : observation
        }
        do {
            let audit = try FaultAuditKernel.close(campaign: campaign, observations: replaced)
            Issue.record("invalid fault result accepted")
            #expect(audit.digest.rawValue.isEmpty)
        } catch let error {
            switch result {
            case .uncontrolled:
                #expect(error == .faultUncontrolled(single.id, point.id))
            case .undetectedRecovered:
                #expect(error == .faultUndetected(single.id, point.id))
            case .recovered, .failedClosed, .unreached, .undetectedFailedClosed, .provenIrrelevant:
                Issue.record("unexpected result branch")
            }
        }
    }
}

@Test
func injectorReportsEveryActivationExactlyOnce() throws {
    let campaign = try StandardFaultCampaign.make()
    for scenario in campaign.scenarios {
        var injector = FaultInjector(scenario: scenario)
        for point in scenario.activations {
            #expect(injector.outcome(at: point.id) == point.outcome)
            #expect(injector.outcome(at: point.id) == nil)
        }
        #expect(injector.unreachedPoints().isEmpty)
    }
}

@Test
func propertyRunnerShrinksFailuresDeterministically() throws {
    let iterations = try IterationCount.positive(64)
    let generator = try PropertyGenerator<Int>.integers(in: 1...100)
    let result = try PropertyRunner.check(
        iterations: iterations,
        seed: 7,
        generator: generator,
        shrinker: .towardZero,
        predicate: { $0 == 0 }
    )
    switch result {
    case .failed(let value, let iteration):
        #expect(value == 1)
        #expect(iteration.rawValue == 1)
    case .passed(let count):
        Issue.record("unexpected property pass")
        #expect(count.rawValue == 0)
    }
}

private func worldSpace() throws -> WorldSpace {
    let device = DeviceProfile(id: try DeviceID.parse("device-1"), family: .phone)
    let schedule = ScheduleScenario(id: try ScheduleID.parse("schedule-1"), decisions: [])
    return WorldSpace(
        builds: .enumerated([.debug, .release]),
        operatingSystems: .enumerated([.iOS]),
        devices: .enumerated([device]),
        locales: .enumerated([.englishUnitedStates]),
        layoutDirections: .enumerated([.leftToRight]),
        appearances: .enumerated([.light, .dark]),
        accessibilityScenarios: .enumerated([.standard]),
        permissions: .enumerated([PermissionScenario(kind: .camera, state: .granted)]),
        locations: .enumerated([.fixed]),
        biometrics: .enumerated([.succeeds]),
        lifecycles: .enumerated([.foreground]),
        dataScenarios: .enumerated([.typical]),
        serviceFaults: .enumerated([.none]),
        cancellations: .enumerated([.never]),
        schedules: .enumerated([schedule]),
        mutants: .enumerated([.clean])
    )
}
