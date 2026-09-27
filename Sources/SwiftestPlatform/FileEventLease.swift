import Foundation
import SwiftestModel

public enum WatchedInputKind: Sendable {
    case file
    case directory
}

public struct WatchedInput: Sendable {
    public let path: String
    public let kind: WatchedInputKind

    public init(path: String, kind: WatchedInputKind) {
        self.path = path
        self.kind = kind
    }
}

public struct FileEventGeneration: Equatable, Sendable {
    private let value: UInt64

    private init(_ value: UInt64) {
        self.value = value
    }

    fileprivate static let initial = FileEventGeneration(0)

    fileprivate func advanced() -> FileEventGeneration? {
        let next = value.addingReportingOverflow(1)
        guard !next.overflow else {
            return nil
        }
        return FileEventGeneration(next.partialValue)
    }

    fileprivate var decimalText: String {
        String(value)
    }

    fileprivate static func successorText(_ raw: UInt64) -> String {
        guard let next = FileEventGeneration(raw).advanced() else {
            return "overflow"
        }
        return next.decimalText
    }
}

public struct FileEventWitness: Equatable, Sendable {
    public let continuity: FileEventContinuity
    public let generation: FileEventGeneration

    static let initial = FileEventWitness(continuity: .eventFree, generation: .initial)

    fileprivate init(continuity: FileEventContinuity, generation: FileEventGeneration) {
        self.continuity = continuity
        self.generation = generation
    }

    public func including(_ continuity: FileEventContinuity) -> FileEventWitness {
        FileEventWitness(continuity: self.continuity.joined(with: continuity), generation: generation)
    }

    func recordingAttributeEvent() -> FileEventWitness? {
        guard let next = generation.advanced() else {
            return nil
        }
        return FileEventWitness(continuity: .attributeAmbiguous, generation: next)
    }
}

struct FileEventHealth: Equatable, Sendable {
    let witness: FileEventWitness
    let firstAttributePath: WatchedPath?

    static let initial = FileEventHealth(witness: .initial, firstAttributePath: nil)

    private init(witness: FileEventWitness, firstAttributePath: WatchedPath?) {
        self.witness = witness
        self.firstAttributePath = firstAttributePath
    }

    func including(_ continuity: FileEventContinuity) -> FileEventHealth {
        FileEventHealth(witness: witness.including(continuity), firstAttributePath: firstAttributePath)
    }

    func advanceForAttribute(at path: WatchedPath) -> FileEventHealth? {
        guard let next = witness.recordingAttributeEvent() else {
            return nil
        }
        let first: WatchedPath
        if let firstAttributePath {
            first = firstAttributePath
        } else {
            first = path
        }
        return FileEventHealth(witness: next, firstAttributePath: first)
    }

    func requireEventFree() throws(PlatformError) {
        switch witness.continuity {
        case .eventFree:
            return
        case .attributeAmbiguous:
            guard let firstAttributePath else {
                throw .attributeOriginMissing
            }
            throw .attributeAmbiguous(firstAttributePath)
        }
    }
}

public enum LeaseWitnessOracle {
    public static func text() throws(PlatformError) -> String {
        let initial = FileEventWitness.initial
        guard let first = initial.recordingAttributeEvent(),
            let second = first.recordingAttributeEvent(),
            let third = second.recordingAttributeEvent(),
            let fourth = third.recordingAttributeEvent() else {
            throw .eventGenerationOverflow
        }
        let samples: [(Int, FileEventWitness)] = [
            (0, initial), (1, first), (2, second), (4, fourth),
        ]
        var lines = samples.map { count, witness in
            ["lease-witness", String(count), witness.continuity.rawValue,
                witness.generation.decimalText].joined(separator: "\t")
        }
        let boundaries: [UInt64] = [0, 18_446_744_073_709_551_614, UInt64.max]
        for value in boundaries {
            lines.append(["lease-generation", String(value), FileEventGeneration.successorText(value)]
                .joined(separator: "\t"))
        }
        guard let firstPath = WatchedPath.validated("/swiftest/oracle/first"),
            let secondPath = WatchedPath.validated("/swiftest/oracle/second"),
            let firstHealth = FileEventHealth.initial.advanceForAttribute(at: firstPath),
            let secondHealth = firstHealth.advanceForAttribute(at: secondPath) else {
            throw .attributeOriginMissing
        }
        let originSamples: [(Int, FileEventHealth)] = [
            (0, .initial), (1, firstHealth), (2, secondHealth),
        ]
        for (count, health) in originSamples {
            let origin: String
            switch health.firstAttributePath {
            case .none:
                origin = "absent"
            case .some(let path) where path == firstPath:
                origin = "1"
            case .some(let path) where path == secondPath:
                origin = "2"
            case .some:
                throw .attributeOriginMissing
            }
            lines.append([
                "lease-origin", String(count), origin,
                health.witness.generation.decimalText,
                health.witness.continuity.rawValue,
            ].joined(separator: "\t"))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

public struct FileEventLease: ~Copyable {
    private enum Health {
        case active(FileEventHealth)
        case invalid(PlatformError)
    }

    private final class HealthCell {
        private let lock = NSLock()
        private var state: Health = .active(.initial)

        var snapshot: Health {
            lock.lock()
            defer {
                lock.unlock()
            }
            return state
        }

        func complete(_ observed: FileEventContinuity) -> Health {
            lock.lock()
            defer {
                lock.unlock()
            }
            switch state {
            case .active(let prior):
                state = .active(prior.including(observed))
                return state
            case .invalid:
                return state
            }
        }

        func recordAttributeEvent(at path: WatchedPath) -> PlatformError? {
            lock.lock()
            defer {
                lock.unlock()
            }
            switch state {
            case .active(let prior):
                guard let next = prior.advanceForAttribute(at: path) else {
                    let error = PlatformError.eventGenerationOverflow
                    state = .invalid(error)
                    return error
                }
                state = .active(next)
                return nil
            case .invalid(let error):
                return error
            }
        }

        func invalidate(_ error: PlatformError) -> PlatformError {
            lock.lock()
            defer {
                lock.unlock()
            }
            switch state {
            case .active:
                state = .invalid(error)
                return error
            case .invalid(let prior):
                return prior
            }
        }
    }

    private let queue: ABIAdapter.VnodeEventQueue
    private let health: HealthCell

    public init(inputs: [WatchedInput]) throws(PlatformError) {
        guard !inputs.isEmpty else {
            throw .watch("empty-input-inventory")
        }
        guard var opened = ABIAdapter.VnodeEventQueue() else {
            throw .watch("event-queue")
        }
        for input in inputs {
            switch opened.register(input) {
            case .registered:
                continue
            case .unavailable:
                throw .watch(input.path)
            }
        }
        self.queue = consume opened
        self.health = HealthCell()
    }

    public borrowing func observeUnchanged() throws(PlatformError) -> FileEventWitness {
        switch health.snapshot {
        case .active:
            break
        case .invalid(let error):
            throw error
        }
        var transition: LeaseTransition
        do {
            transition = try LeaseTransition.begin(registrationCount: queue.registrationCount)
        } catch let error {
            switch error {
            case .emptyInventory:
                throw health.invalidate(.watch("empty-input-inventory"))
            case .inventoryOverflow:
                throw health.invalidate(.watch("event-inventory-overflow"))
            }
        }
        while true {
            let event = queue.nextEvent()
            if case .attributeAmbiguous(let path) = event,
                let error = health.recordAttributeEvent(at: path) {
                throw error
            }
            switch transition.observing(Self.observation(for: event)) {
            case .verified(let continuity):
                switch health.complete(continuity) {
                case .active(let active):
                    return active.witness
                case .invalid(let error):
                    throw error
                }
            case .invalid:
                throw health.invalidate(Self.failure(for: event))
            case .polling(let budget, let continuity):
                transition = .polling(budget, continuity)
                continue
            }
        }
    }

    public borrowing func verifyUnchanged() throws(PlatformError) -> FileEventContinuity {
        try observeUnchanged().continuity
    }

    public borrowing func requireEventFree() throws(PlatformError) {
        switch try observeUnchanged().continuity {
        case .eventFree:
            return
        case .attributeAmbiguous:
            switch health.snapshot {
            case .active(let active):
                try active.requireEventFree()
            case .invalid(let error):
                throw error
            }
        }
    }

    private static func observation(for event: ABIAdapter.VnodeEvent) -> LeaseObservation {
        switch event {
        case .none:
            .quiescent
        case .attributeAmbiguous:
            .attributeAmbiguous
        case .mutation:
            .mutation
        case .unknownDescriptor:
            .unknownDescriptor
        case .unavailable:
            .queueUnavailable
        }
    }

    private static func failure(for event: ABIAdapter.VnodeEvent) -> PlatformError {
        switch event {
        case .none:
            .watch("invalid-quiet-transition")
        case .attributeAmbiguous:
            .watch("event-queue-not-quiescent")
        case .mutation(let path):
            .changedWhileWatched(path)
        case .unknownDescriptor:
            .watch("unknown-event-descriptor")
        case .unavailable:
            .watch("event-queue")
        }
    }
}
