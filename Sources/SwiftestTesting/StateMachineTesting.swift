import SwiftestModel

public enum StateMachineError: Error, Equatable, Sendable {
    case emptyActions
    case exploredCountOverflow
}

public struct StateMachineModel<State: Sendable, Action: Sendable>: Sendable {
    public let initialState: State
    public let actions: [Action]
    private let transition: @Sendable (State, Action) -> State
    private let invariant: @Sendable (State) -> Bool

    public init(
        initialState: State,
        actions: [Action],
        transition: @escaping @Sendable (State, Action) -> State,
        invariant: @escaping @Sendable (State) -> Bool
    ) throws(StateMachineError) {
        guard !actions.isEmpty else {
            throw .emptyActions
        }
        self.initialState = initialState
        self.actions = actions
        self.transition = transition
        self.invariant = invariant
    }

    public func nextState(from state: State, action: Action) -> State {
        transition(state, action)
    }

    public func accepts(_ state: State) -> Bool {
        invariant(state)
    }
}

public enum StateMachineResult<Action: Sendable>: Sendable {
    case passed(explored: EvidenceCount)
    case failed(trace: [Action])
}

private struct ExplorationFrame<State: Sendable, Action: Sendable> {
    let state: State
    let incomingAction: Action?
    var nextActionIndex: Int
    var evaluated: Bool
}

public enum StateMachineRunner {
    public static func explore<State: Sendable, Action: Sendable>(
        model: StateMachineModel<State, Action>,
        depth: IterationCount
    ) throws(StateMachineError) -> StateMachineResult<Action> {
        var pending = [ExplorationFrame(
            state: model.initialState,
            incomingAction: Optional<Action>.none,
            nextActionIndex: 0,
            evaluated: false
        )]
        var shortestFailure: [Action]?
        var explored = 0
        while var frame = pending.popLast() {
            if !frame.evaluated {
                let increment = explored.addingReportingOverflow(1)
                guard !increment.overflow else {
                    throw .exploredCountOverflow
                }
                explored = increment.partialValue
                if !model.accepts(frame.state) {
                    var trace = pending.compactMap(\.incomingAction)
                    if let action = frame.incomingAction {
                        trace.append(action)
                    }
                    if let previous = shortestFailure {
                        if trace.count < previous.count {
                            shortestFailure = trace
                        }
                    } else {
                        shortestFailure = trace
                    }
                    continue
                }
                frame.evaluated = true
            }
            if pending.count < depth.rawValue && frame.nextActionIndex < model.actions.count {
                let action = model.actions[frame.nextActionIndex]
                frame.nextActionIndex += 1
                let child = ExplorationFrame(
                    state: model.nextState(from: frame.state, action: action),
                    incomingAction: action,
                    nextActionIndex: 0,
                    evaluated: false
                )
                pending.append(frame)
                pending.append(child)
            }
        }
        if let shortestFailure {
            return .failed(trace: shortestFailure)
        }
        do {
            return .passed(explored: try EvidenceCount.nonnegative(explored))
        } catch {
            throw .exploredCountOverflow
        }
    }
}
