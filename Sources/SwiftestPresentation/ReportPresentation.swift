import SwiftestDecision
import SwiftestModel
import SwiftestReport
import SwiftestScore

public enum ReportPresentation {
    public static func text(_ report: AssuredReport) -> String {
        [
            "verdict=" + report.catalog.verdict.rawValue,
            "run=" + report.catalog.evidence.run.rawValue,
            "scope=" + report.catalog.evidence.scope.rawValue,
            "score=" + report.score.ratioDescription,
            "executions=" + String(report.catalog.evidence.executionCount.rawValue),
            "fault-scenarios=" + String(report.faults.scenarioCount.rawValue),
        ].joined(separator: "\n") + "\n"
    }
}
