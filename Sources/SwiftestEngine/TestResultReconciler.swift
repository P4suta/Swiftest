import SwiftestModel

public enum TestResultEvidence: Equatable, Sendable {
    case xunit(
        total: EvidenceCount,
        failed: EvidenceCount,
        errors: EvidenceCount,
        skipped: EvidenceCount
    )
    case xcresult(
        status: XCResultStatus,
        total: EvidenceCount,
        passed: EvidenceCount,
        failed: EvidenceCount,
        skipped: EvidenceCount,
        expectedFailures: EvidenceCount,
        failureRecords: EvidenceCount
    )
}

public enum TestResultConflict: String, Equatable, Sendable {
    case inconsistentCounts = "result counts disagree"
    case noExecutedTests = "no test cases executed"
    case skippedCases = "test cases were skipped"
    case expectedFailures = "expected failures require independent claim evidence"
    case unknownStatus = "test result status is unknown"
    case inconsistentStatus = "test result status disagrees with counts"
    case failureRecords = "failed tests and failure records disagree"
    case exitDisagreement = "runner exit disagrees with test result"
}

public enum TestResultReconciliation: Equatable, Sendable {
    case passed(EvidenceCount)
    case failed(EvidenceCount)
    case apparatus(TestResultConflict)
}

public enum TestResultReconciler {
    public static func reconcile(
        exitCode: Int32,
        evidence: TestResultEvidence
    ) -> TestResultReconciliation {
        switch evidence {
        case .xunit(let total, let failed, let errors, let skipped):
            guard let classified = sum([failed, errors, skipped]),
                let failureCount = sum([failed, errors]),
                classified <= total.rawValue else {
                return .apparatus(.inconsistentCounts)
            }
            guard let executed = executed(total: total, skipped: skipped) else {
                return .apparatus(.inconsistentCounts)
            }
            if executed.rawValue == 0 {
                return .apparatus(.noExecutedTests)
            }
            if skipped.rawValue > 0 {
                return .apparatus(.skippedCases)
            }
            return classify(exitCode: exitCode, failureCount: failureCount, executed: executed)
        case .xcresult(
            let status,
            let total,
            let passed,
            let failed,
            let skipped,
            let expectedFailures,
            let failureRecords
        ):
            guard let classified = sum([passed, failed, skipped, expectedFailures]),
                classified == total.rawValue else {
                return .apparatus(.inconsistentCounts)
            }
            guard let executed = executed(total: total, skipped: skipped) else {
                return .apparatus(.inconsistentCounts)
            }
            if executed.rawValue == 0 {
                return .apparatus(.noExecutedTests)
            }
            if skipped.rawValue > 0 || status == .skipped {
                return .apparatus(.skippedCases)
            }
            if expectedFailures.rawValue > 0 {
                return .apparatus(.expectedFailures)
            }
            if status == .unknown {
                return .apparatus(.unknownStatus)
            }
            if (failed.rawValue == 0) != (failureRecords.rawValue == 0) {
                return .apparatus(.failureRecords)
            }
            switch status {
            case .passed:
                if failed.rawValue > 0 {
                    return .apparatus(.inconsistentStatus)
                }
            case .failed:
                if failed.rawValue == 0 {
                    return .apparatus(.inconsistentStatus)
                }
            case .expectedFailure:
                return .apparatus(.inconsistentStatus)
            case .skipped, .unknown:
                return .apparatus(.unknownStatus)
            }
            return classify(exitCode: exitCode, failureCount: failed.rawValue, executed: executed)
        }
    }

    private static func classify(
        exitCode: Int32,
        failureCount: Int,
        executed: EvidenceCount
    ) -> TestResultReconciliation {
        if exitCode == 0 && failureCount == 0 {
            return .passed(executed)
        }
        if exitCode != 0 && failureCount > 0 {
            return .failed(executed)
        }
        return .apparatus(.exitDisagreement)
    }

    private static func executed(
        total: EvidenceCount,
        skipped: EvidenceCount
    ) -> EvidenceCount? {
        let difference = total.rawValue.subtractingReportingOverflow(skipped.rawValue)
        if difference.overflow {
            return nil
        }
        do {
            return try .nonnegative(difference.partialValue)
        } catch {
            return nil
        }
    }

    private static func sum(_ counts: [EvidenceCount]) -> Int? {
        var accumulated = 0
        for count in counts {
            let next = accumulated.addingReportingOverflow(count.rawValue)
            if next.overflow {
                return nil
            }
            accumulated = next.partialValue
        }
        return accumulated
    }
}
