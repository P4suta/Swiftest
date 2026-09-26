import SwiftestModel

public enum VerdictOracle {
    public static func text() -> String {
        var lines: [String] = []
        for apparatus in EvidenceSignal.allCases {
            for gap in EvidenceSignal.allCases {
                for unsettled in EvidenceSignal.allCases {
                    for scope in ScopeKind.allCases {
                        let verdict = VerdictDecision.decide(DecisionSignals(
                            apparatusFailure: apparatus,
                            gap: gap,
                            unsettled: unsettled,
                            scope: scope
                        ))
                        lines.append([
                            apparatus.rawValue,
                            gap.rawValue,
                            unsettled.rawValue,
                            scope.rawValue,
                            verdict.rawValue,
                        ].joined(separator: "\t"))
                    }
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
