import SwiftestModel
import SwiftestTesting
import Testing

@WorldTest
func worldTestMacroRunsAsTestingTest() {
    #invariant(true)
    #eventually(true)
}

@WorldUITest
func worldUITestMacroRunsAsTestingTest() {
    #invariant(true)
}

@Property
func propertyMacroRunsAsTestingTest() {
    #invariant(true)
}

@StateMachineTest
func stateMachineMacroRunsAsTestingTest() {
    #invariant(true)
}

@PerformanceClaim
func performanceMacroRunsAsTestingTest() {
    #invariant(true)
}

@Test
func temporalAssertionsObserveAllAttempts() async throws {
    let attempts = try IterationCount.positive(3)
    let counter = AttemptCounter()
    try await TemporalAssertions.eventually(attempts: attempts) {
        await counter.incrementAndReach(3)
    }
    #expect(await counter.value() == 3)
    try await TemporalAssertions.invariant(observations: attempts) {
        true
    }
    try await TemporalAssertions.never(observations: attempts) {
        false
    }
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
