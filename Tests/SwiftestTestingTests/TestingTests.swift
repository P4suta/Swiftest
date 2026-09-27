import SwiftestEngine
import SwiftestModel
import SwiftestTesting
import Testing

@Test
@WorldTest(worlds: try macroWorldSpace(), body: verifyWorld)
func worldTestVisitsEverySelectedWorld() async throws {}

@Test
@WorldUITest(worlds: try macroWorldSpace(), body: verifyWorld)
func worldUITestVisitsEverySelectedWorld() async throws {}

@Test
@Property(
    iterations: try IterationCount.positive(17),
    seed: 7,
    range: -10...10,
    predicate: { value in value >= -10 && value <= 10 }
)
func propertyChecksEveryGeneratedInteger() throws {}

@Test
@StateMachineTest(model: try passingStateMachine(), depth: try .positive(3))
func stateMachineMacroExploresFiniteTransitions() throws {}

@ClosedDomain
enum MacroSpecimen: Equatable, Sendable {
    case first
    case second
}

@ClosedDomain
public enum PublicMacroSpecimen: String, Equatable, Sendable {
    case `default` = "wire"
    case ready
}

@Test
func closedDomainMacroGeneratesEveryRepresentation() {
    #expect(MacroSpecimen.cases == [.first, .second])
    #expect(MacroSpecimen.first.code == "first")
    #expect(MacroSpecimen.second.code == "second")
    #expect(MacroSpecimen.testSpecimens == [.first, .second])
    #expect(MacroSpecimen.schema == "{\"additionalProperties\":false,\"enum\":[\"first\",\"second\"],\"title\":\"MacroSpecimen\",\"type\":\"string\"}")
    #expect(PublicMacroSpecimen.cases == [.`default`, .ready])
    #expect(PublicMacroSpecimen.`default`.code == "default")
    #expect(PublicMacroSpecimen.`default`.rawValue == "wire")
}

@Test
func stateMachineRunnerExploresEveryTraceAndReportsShortestFailure() throws {
    let depth = try IterationCount.positive(3)
    let passing = try StateMachineRunner.explore(model: passingStateMachine(), depth: depth)
    switch passing {
    case .passed(let explored):
        #expect(explored.rawValue == 15)
    case .failed:
        Issue.record("a passing state machine failed")
    }
    let failingModel = try StateMachineModel(
        initialState: 0,
        actions: [-1, 1],
        transition: { state, action in state + action },
        invariant: { state in state >= -1 }
    )
    let failing = try StateMachineRunner.explore(model: failingModel, depth: depth)
    switch failing {
    case .passed:
        Issue.record("a failing state machine passed")
    case .failed(let trace):
        #expect(trace == [-1, -1])
    }
    let laterShorterModel = try StateMachineModel(
        initialState: 0,
        actions: [1, -1],
        transition: { state, action in state + action },
        invariant: { state in state >= 0 }
    )
    let laterShortest = try StateMachineRunner.explore(model: laterShorterModel, depth: depth)
    switch laterShortest {
    case .passed:
        Issue.record("a shorter later failure was missed")
    case .failed(let trace):
        #expect(trace == [-1])
    }
}

@Test
func stateMachineModelRejectsEmptyActions() {
    do {
        let model = try StateMachineModel<Int, Int>(
            initialState: 0,
            actions: [],
            transition: { state, action in state + action },
            invariant: { state in state >= 0 }
        )
        Issue.record("an empty action set was accepted")
        #expect(model.actions.isEmpty)
    } catch let error {
        #expect(error == .emptyActions)
    }
}

@Test
func temporalMacrosObserveAllAttempts() async throws {
    let attempts = try IterationCount.positive(3)
    let counter = AttemptCounter()
    try await #eventually(attempts: attempts) {
        await counter.incrementAndReach(3)
    }
    #expect(await counter.value() == 3)
    try await #invariant(observations: attempts) {
        true
    }
    try await #never(observations: attempts) {
        false
    }
    try await #never(observations: attempts, { false })
}

@Test
func temporalMacroFailsWhenAnyObservationViolatesClaim() async throws {
    let attempts = try IterationCount.positive(2)
    do {
        try await #never(observations: attempts) {
            true
        }
        Issue.record("#never accepted a true observation")
    } catch let error {
        #expect(error == .neverFailed(attempts))
    }
}

@Test
func eventualMacroRejectsExhaustedObservations() async throws {
    let attempts = try IterationCount.positive(2)
    let counter = AttemptCounter()
    do {
        try await #eventually(attempts: attempts) {
            await counter.incrementAndReach(3)
        }
        Issue.record("#eventually accepted an unmet condition")
    } catch let error {
        #expect(error == .eventuallyFailed(attempts))
    }
    #expect(await counter.value() == 2)
}

@Test
func invariantMacroRejectsFirstViolation() async throws {
    let observations = try IterationCount.positive(3)
    let counter = AttemptCounter()
    do {
        try await #invariant(observations: observations) {
            await counter.incrementAndReach(1)
        }
        Issue.record("#invariant accepted a false observation")
    } catch let error {
        #expect(error == .invariantFailed(observations))
    }
    #expect(await counter.value() == 2)
}

private actor AttemptCounter {
    private var count = 0

    func incrementAndReach(_ target: Int) -> Bool {
        count += 1
        return count == target
    }

    func value() -> Int {
        count
    }
}

private func verifyWorld(_ world: World) async throws {
    #expect(world.id.rawValue.hasPrefix("world-v1-"))
    #expect(try WorldID.parse(world.id.rawValue) == world.id)
    #expect(world.appearance == .light || world.appearance == .dark)
}

private func passingStateMachine() throws -> StateMachineModel<Int, Int> {
    try StateMachineModel(
        initialState: 0,
        actions: [0, 1],
        transition: { state, action in state + action },
        invariant: { state in state >= 0 }
    )
}

private func macroWorldSpace() throws -> WorldSpace {
    let device = DeviceProfile(id: try DeviceID.parse("device-1"), family: .phone)
    let schedule = ScheduleScenario(id: try ScheduleID.parse("schedule-1"), decisions: [])
    return WorldSpace(
        builds: .enumerated([.debug]),
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
