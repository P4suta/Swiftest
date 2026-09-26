public enum VerdictInput: String, CaseIterable, Sendable {
    case absent
    case present
}

public struct VerdictInputs: Equatable, Sendable {
    public let apparatusFailure: VerdictInput
    public let gap: VerdictInput
    public let unsettled: VerdictInput
    public let scope: ScopeKind

    public init(
        apparatusFailure: VerdictInput,
        gap: VerdictInput,
        unsettled: VerdictInput,
        scope: ScopeKind
    ) {
        self.apparatusFailure = apparatusFailure
        self.gap = gap
        self.unsettled = unsettled
        self.scope = scope
    }
}

public enum VerdictPolicy {
    public static func decide(_ inputs: VerdictInputs) -> Verdict {
        if inputs.apparatusFailure == .present {
            return .invalid
        }
        if inputs.gap == .present && inputs.unsettled == .present {
            return .gapsAndUnsettled
        }
        if inputs.gap == .present {
            return .gaps
        }
        if inputs.unsettled == .present {
            return .unsettled
        }
        switch inputs.scope {
        case .complete:
            return .assured
        case .change:
            return .changeAssured
        case .scoped:
            return .scopeAssured
        }
    }

    public static func inputs(for catalog: EvidenceCatalog) -> VerdictInputs {
        VerdictInputs(
            apparatusFailure: catalog.hasApparatusFailure ? .present : .absent,
            gap: catalog.hasGapEvidence ? .present : .absent,
            unsettled: catalog.hasUnsettledEvidence ? .present : .absent,
            scope: catalog.scope
        )
    }
}
