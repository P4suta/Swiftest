public enum AbstractFaultResult: String, CaseIterable, Sendable {
    case recovered
    case failedClosed = "failed-closed"
    case provenIrrelevant = "proven-irrelevant"
    case unreached
    case uncontrolled
    case undetected
}

public enum FaultAcceptance: String, Sendable {
    case accepted
    case rejected
}

public enum FaultOracle {
    public static func acceptance(of result: AbstractFaultResult) -> FaultAcceptance {
        switch result {
        case .recovered, .failedClosed, .provenIrrelevant:
            .accepted
        case .unreached, .uncontrolled, .undetected:
            .rejected
        }
    }

    public static func text() -> String {
        AbstractFaultResult.allCases.map { result in
            ["fault", result.rawValue, acceptance(of: result).rawValue].joined(separator: "\t")
        }.joined(separator: "\n") + "\n"
    }
}
