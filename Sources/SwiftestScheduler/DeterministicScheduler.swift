import SwiftestModel
import SwiftestSolver

public enum SchedulerError: Error, Equatable, Sendable {
    case invalidResource(String)
    case duplicateAction(String)
    case invalidTask(Int)
    case scheduleIdentifier(IdentifierError)
    case reductionUnsound
}

public struct ResourceID: Hashable, Sendable, Comparable {
    public let rawValue: String

    private init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func parse(_ value: String) throws(SchedulerError) -> ResourceID {
        if value.isEmpty {
            throw .invalidResource(value)
        }
        return ResourceID(rawValue: value)
    }

    public static func < (lhs: ResourceID, rhs: ResourceID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum AccessMode: String, CaseIterable, Hashable, Sendable {
    case read
    case write
}

public struct ResourceAccess: Hashable, Sendable {
    public let resource: ResourceID
    public let mode: AccessMode

    public init(resource: ResourceID, mode: AccessMode) {
        self.resource = resource
        self.mode = mode
    }
}

public struct ScheduledAction: Hashable, Sendable {
    public let id: String
    public let task: Int
    public let accesses: Set<ResourceAccess>

    public init(id: String, task: Int, accesses: Set<ResourceAccess>) throws(SchedulerError) {
        if id.isEmpty {
            throw .duplicateAction(id)
        }
        if task < 0 {
            throw .invalidTask(task)
        }
        self.id = id
        self.task = task
        self.accesses = accesses
    }

    public func isIndependent(from other: ScheduledAction) -> Bool {
        if task == other.task {
            return false
        }
        for left in accesses {
            for right in other.accesses where left.resource == right.resource {
                if left.mode == .write || right.mode == .write {
                    return false
                }
            }
        }
        return true
    }
}

public struct ScheduleTrace: Hashable, Sendable {
    public let id: ScheduleID
    public let actions: [ScheduledAction]

    public init(id: ScheduleID, actions: [ScheduledAction]) {
        self.id = id
        self.actions = actions
    }
}

public enum CancellationPoint: Hashable, Sendable {
    case beforeStart
    case afterAction(Int)
    case afterCompletion
}

public enum DeterministicScheduler {
    public static func traces(
        tasks: [[ScheduledAction]],
        proofMode: ProofMode
    ) throws(SchedulerError) -> [ScheduleTrace] {
        let flattened = tasks.flatMap { $0 }
        if Set(flattened.map(\.id)).count != flattened.count {
            throw .duplicateAction("schedule")
        }
        var all: [[ScheduledAction]] = []
        enumerate(tasks: tasks, positions: Array(repeating: 0, count: tasks.count), prefix: [], output: &all)
        let selected: [[ScheduledAction]]
        switch proofMode {
        case .disabled:
            selected = all
        case .enabled:
            var seen = Set<[String]>()
            var reduced: [[ScheduledAction]] = []
            for trace in all {
                let canonical = canonicalActionIDs(trace)
                let inserted = seen.insert(canonical)
                if inserted.inserted {
                    reduced.append(trace)
                }
            }
            selected = reduced
        }
        var traces: [ScheduleTrace] = []
        traces.reserveCapacity(selected.count)
        for (index, actions) in selected.enumerated() {
            let raw = "schedule-" + String(index)
            do {
                traces.append(ScheduleTrace(id: try ScheduleID.parse(raw), actions: actions))
            } catch let error {
                throw SchedulerError.scheduleIdentifier(error)
            }
        }
        return traces
    }

    public static func cancellationPoints(actionCount: Int) -> [CancellationPoint] {
        var result: [CancellationPoint] = [.beforeStart]
        if actionCount > 0 {
            for index in 0..<actionCount {
                result.append(.afterAction(index))
            }
        }
        result.append(.afterCompletion)
        return result
    }

    private static func enumerate(
        tasks: [[ScheduledAction]],
        positions: [Int],
        prefix: [ScheduledAction],
        output: inout [[ScheduledAction]]
    ) {
        if tasks.indices.allSatisfy({ positions[$0] >= tasks[$0].count }) {
            output.append(prefix)
            return
        }
        for taskIndex in tasks.indices where positions[taskIndex] < tasks[taskIndex].count {
            var nextPositions = positions
            let actionIndex = nextPositions[taskIndex]
            nextPositions[taskIndex] = actionIndex + 1
            var nextPrefix = prefix
            nextPrefix.append(tasks[taskIndex][actionIndex])
            enumerate(tasks: tasks, positions: nextPositions, prefix: nextPrefix, output: &output)
        }
    }

    static func canonicalActionIDs(_ trace: [ScheduledAction]) -> [String] {
        var actions = trace
        var changed = true
        while changed {
            changed = false
            if actions.count < 2 {
                break
            }
            for index in 0..<(actions.count - 1) {
                let left = actions[index]
                let right = actions[index + 1]
                if left.isIndependent(from: right) && left.id > right.id {
                    actions.swapAt(index, index + 1)
                    changed = true
                }
            }
        }
        return actions.map(\.id)
    }
}

public enum DPORProofKernel {
    public static func verify(
        full: [ScheduleTrace],
        reduced: [ScheduleTrace]
    ) throws(SchedulerError) {
        let representatives = Set(reduced.map { DeterministicScheduler.canonicalActionIDs($0.actions) })
        for trace in full {
            let canonical = DeterministicScheduler.canonicalActionIDs(trace.actions)
            if !representatives.contains(canonical) {
                throw .reductionUnsound
            }
        }
    }
}
