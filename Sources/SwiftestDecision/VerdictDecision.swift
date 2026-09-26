import SwiftestModel

public enum EvidenceSignal: String, CaseIterable, Sendable {
    case absent
    case present
}

public struct DecisionSignals: Equatable, Sendable {
    public let apparatusFailure: EvidenceSignal
    public let gap: EvidenceSignal
    public let unsettled: EvidenceSignal
    public let scope: ScopeKind

    public init(
        apparatusFailure: EvidenceSignal,
        gap: EvidenceSignal,
        unsettled: EvidenceSignal,
        scope: ScopeKind
    ) {
        self.apparatusFailure = apparatusFailure
        self.gap = gap
        self.unsettled = unsettled
        self.scope = scope
    }
}

public enum VerdictDecision {
    public static func decide(_ signals: DecisionSignals) -> Verdict {
        if signals.apparatusFailure == .present {
            return .invalid
        }
        if signals.gap == .present && signals.unsettled == .present {
            return .gapsAndUnsettled
        }
        if signals.gap == .present {
            return .gaps
        }
        if signals.unsettled == .present {
            return .unsettled
        }
        switch signals.scope {
        case .complete:
            return .assured
        case .change:
            return .changeAssured
        case .scoped:
            return .scopeAssured
        }
    }

    public static func signals(for catalog: EvidenceCatalog) -> DecisionSignals {
        let apparatusFailure = catalog.failures.contains {
            if case .apparatus = $0 {
                return true
            }
            return false
        }
        let unsettled = catalog.failures.contains {
            if case .clean = $0 {
                return true
            }
            return false
        } || catalog.review.status == .rejected
        let gap = catalog.failures.contains {
            if case .mutant = $0 {
                return true
            }
            return false
        } || catalog.lawObservations.contains(where: { $0.status == .failed })
            || catalog.schemaObservations.contains(where: { $0.status == .failed })
        return DecisionSignals(
            apparatusFailure: apparatusFailure ? .present : .absent,
            gap: gap ? .present : .absent,
            unsettled: unsettled ? .present : .absent,
            scope: catalog.scope
        )
    }
}
