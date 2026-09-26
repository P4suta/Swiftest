import SwiftestModel
import SwiftestPlatform

public enum TemporalAssertionError: Error, Equatable, Sendable {
    case eventuallyFailed(IterationCount)
    case invariantFailed(IterationCount)
    case neverFailed(IterationCount)
}

public enum TemporalAssertions {
    public static func eventually(
        attempts: IterationCount,
        condition: @Sendable () async -> Bool
    ) async throws(TemporalAssertionError) {
        for _ in 0..<attempts.rawValue {
            if await condition() {
                return
            }
            await TaskBoundary.yield()
        }
        throw .eventuallyFailed(attempts)
    }

    public static func invariant(
        observations: IterationCount,
        condition: @Sendable () async -> Bool
    ) async throws(TemporalAssertionError) {
        for _ in 0..<observations.rawValue {
            if !(await condition()) {
                throw .invariantFailed(observations)
            }
            await TaskBoundary.yield()
        }
    }

    public static func never(
        observations: IterationCount,
        condition: @Sendable () async -> Bool
    ) async throws(TemporalAssertionError) {
        for _ in 0..<observations.rawValue {
            if await condition() {
                throw .neverFailed(observations)
            }
            await TaskBoundary.yield()
        }
    }
}
