public enum LeaseObservation: Equatable, Sendable {
    case quiescent
    case attributeAmbiguous
    case mutation
    case unknownDescriptor
    case queueUnavailable
}

public enum LeaseTransitionError: Error, Equatable, Sendable {
    case emptyInventory
    case inventoryOverflow
}

public struct LeasePollBudget: Equatable, Sendable {
    public let remainingAttributes: Int

    private init(remainingAttributes: Int) {
        self.remainingAttributes = remainingAttributes
    }

    fileprivate static func inventory(_ count: Int) throws(LeaseTransitionError) -> LeasePollBudget {
        guard count > 0 else {
            throw .emptyInventory
        }
        let allowance = count.multipliedReportingOverflow(by: 4)
        guard !allowance.overflow else {
            throw .inventoryOverflow
        }
        return LeasePollBudget(remainingAttributes: allowance.partialValue)
    }

    fileprivate func consumingAttribute() -> LeasePollBudget? {
        guard remainingAttributes > 0 else {
            return nil
        }
        return LeasePollBudget(remainingAttributes: remainingAttributes - 1)
    }
}

public enum LeaseTransition: Equatable, Sendable {
    case polling(LeasePollBudget, FileEventContinuity)
    case verified(FileEventContinuity)
    case invalid

    public static func begin(registrationCount: Int) throws(LeaseTransitionError) -> LeaseTransition {
        .polling(try .inventory(registrationCount), .eventFree)
    }

    public func observing(_ observation: LeaseObservation) -> LeaseTransition {
        switch self {
        case .polling(let budget, let continuity):
            switch observation {
            case .quiescent:
                return .verified(continuity)
            case .attributeAmbiguous:
                guard let next = budget.consumingAttribute() else {
                    return .invalid
                }
                return .polling(next, continuity.joined(with: .attributeAmbiguous))
            case .mutation, .unknownDescriptor, .queueUnavailable:
                return .invalid
            }
        case .verified(let continuity):
            return .verified(continuity)
        case .invalid:
            return .invalid
        }
    }
}
