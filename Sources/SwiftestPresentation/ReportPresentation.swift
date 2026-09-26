import SwiftestDecision
import SwiftestModel
import SwiftestReport
import SwiftestScore

public enum ReportPresentation {
    public static func text(_ report: AssuredReport) -> String {
        let faultSummary: String
        switch report.faults {
        case .structural(let audit):
            faultSummary = "faults=structural scenarios=" + String(audit.scenarioCount.rawValue)
        case .unverified:
            faultSummary = "faults=unverified"
        }
        return [
            "verdict=" + report.verdict.rawValue,
            "run=" + report.catalog.evidence.run.rawValue,
            "scope=" + report.catalog.evidence.scope.rawValue,
            "score=" + report.score.ratioDescription,
            "executions=" + String(report.catalog.evidence.executionCount.rawValue),
            faultSummary,
        ].joined(separator: "\n") + "\n"
    }
}
