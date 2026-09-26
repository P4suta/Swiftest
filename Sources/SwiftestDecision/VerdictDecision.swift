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
        VerdictPolicy.decide(VerdictInputs(
            apparatusFailure: signals.apparatusFailure == .present ? .present : .absent,
            gap: signals.gap == .present ? .present : .absent,
            unsettled: signals.unsettled == .present ? .present : .absent,
            scope: signals.scope
        ))
    }

    public static func signals(for catalog: EvidenceCatalog) -> DecisionSignals {
        return DecisionSignals(
            apparatusFailure: catalog.hasApparatusFailure ? .present : .absent,
            gap: catalog.hasGapEvidence ? .present : .absent,
            unsettled: catalog.hasUnsettledEvidence ? .present : .absent,
            scope: catalog.scope
        )
    }
}
