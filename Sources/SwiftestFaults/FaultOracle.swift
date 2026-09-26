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

public enum BoundaryReach: String, CaseIterable, Sendable {
    case unreached
    case reached
}

public enum BoundaryHandling: Sendable {
    case missing
    case reported(AbstractFaultResult)
}

public enum FaultOracle {
    public static func acceptance(of result: AbstractFaultResult) -> FaultAcceptance {
        switch result {
        case .recovered, .failedClosed:
            .accepted
        case .provenIrrelevant, .unreached, .uncontrolled, .undetected:
            .rejected
        }
    }

    public static func boundaryAcceptance(
        reach: BoundaryReach,
        handling: BoundaryHandling
    ) -> FaultAcceptance {
        switch (reach, handling) {
        case (.unreached, .missing), (.unreached, .reported), (.reached, .missing):
            .rejected
        case (.reached, .reported(let result)):
            acceptance(of: result)
        }
    }

    public static func text() -> String {
        let results = AbstractFaultResult.allCases.map { result in
            ["fault", result.rawValue, acceptance(of: result).rawValue].joined(separator: "\t")
        }
        let handling: [(String, BoundaryHandling)] = [(.init("missing"), .missing)]
            + AbstractFaultResult.allCases.map { ($0.rawValue, .reported($0)) }
        let boundaries = BoundaryReach.allCases.flatMap { reach in
            handling.map { label, result in
                ["fault-boundary", reach.rawValue, label,
                    boundaryAcceptance(reach: reach, handling: result).rawValue]
                    .joined(separator: "\t")
            }
        }
        return (results + boundaries).joined(separator: "\n") + "\n"
    }
}
