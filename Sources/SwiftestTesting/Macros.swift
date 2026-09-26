import SwiftestEngine
import SwiftestModel

@attached(body)
public macro WorldTest(
    worlds: WorldSpace,
    body: @escaping @Sendable (World) async throws -> Void
) = #externalMacro(module: "SwiftestMacros", type: "WorldTestMacro")

@attached(body)
public macro WorldUITest(
    worlds: WorldSpace,
    body: @escaping @Sendable (World) async throws -> Void
) = #externalMacro(module: "SwiftestMacros", type: "WorldUITestMacro")

@attached(body)
public macro Property(
    iterations: IterationCount,
    seed: UInt64,
    range: ClosedRange<Int>,
    predicate: @escaping @Sendable (Int) -> Bool
) = #externalMacro(module: "SwiftestMacros", type: "PropertyMacro")

@attached(body)
public macro StateMachineTest<State: Sendable, Action: Sendable>(
    model: StateMachineModel<State, Action>,
    depth: IterationCount
) = #externalMacro(module: "SwiftestMacros", type: "StateMachineTestMacro")

@attached(peer)
public macro PerformanceClaim() = #externalMacro(module: "SwiftestMacros", type: "PerformanceClaimMacro")

@attached(peer)
public macro TestDouble() = #externalMacro(module: "SwiftestMacros", type: "TestDoubleMacro")

@attached(member, names: named(cases), named(code), named(schema), named(testSpecimens))
public macro ClosedDomain() = #externalMacro(module: "SwiftestMacros", type: "ClosedDomainMacro")

@freestanding(expression)
public macro eventually(
    attempts: IterationCount,
    _ condition: @escaping @Sendable () async -> Bool
) -> Void = #externalMacro(module: "SwiftestMacros", type: "EventuallyMacro")

@freestanding(expression)
public macro invariant(
    observations: IterationCount,
    _ condition: @escaping @Sendable () async -> Bool
) -> Void = #externalMacro(module: "SwiftestMacros", type: "InvariantMacro")

@freestanding(expression)
public macro never(
    observations: IterationCount,
    _ condition: @escaping @Sendable () async -> Bool
) -> Void = #externalMacro(module: "SwiftestMacros", type: "NeverMacro")
