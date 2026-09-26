import SwiftestEngine
import SwiftestModel
import Testing

@Test
func xunitResultReconciliationRejectsPartialOrContradictoryRuns() throws {
    let zero = EvidenceCount.zero
    let one = try EvidenceCount.nonnegative(1)
    let two = try EvidenceCount.nonnegative(2)
    let maximum = try EvidenceCount.nonnegative(Int.max)
    let rows: [(String, Int32, TestResultEvidence, TestResultReconciliation)] = [
        ("clean pass", 0, .xunit(total: two, failed: zero, errors: zero, skipped: zero), .passed(two)),
        ("test failure", 1, .xunit(total: two, failed: one, errors: zero, skipped: zero), .failed(two)),
        ("test error", 1, .xunit(total: two, failed: zero, errors: one, skipped: zero), .failed(two)),
        ("failure with zero exit", 0, .xunit(total: two, failed: one, errors: zero, skipped: zero), .apparatus(.exitDisagreement)),
        ("nonzero exit without failure", 1, .xunit(total: two, failed: zero, errors: zero, skipped: zero), .apparatus(.exitDisagreement)),
        ("empty", 0, .xunit(total: zero, failed: zero, errors: zero, skipped: zero), .apparatus(.noExecutedTests)),
        ("partial skip", 0, .xunit(total: two, failed: zero, errors: zero, skipped: one), .apparatus(.skippedCases)),
        ("all skipped", 0, .xunit(total: one, failed: zero, errors: zero, skipped: one), .apparatus(.noExecutedTests)),
        ("failure count exceeds total", 1, .xunit(total: one, failed: two, errors: zero, skipped: zero), .apparatus(.inconsistentCounts)),
        ("count overflow", 1, .xunit(total: maximum, failed: maximum, errors: one, skipped: zero), .apparatus(.inconsistentCounts)),
    ]
    for (name, exitCode, evidence, expected) in rows {
        #expect(TestResultReconciler.reconcile(exitCode: exitCode, evidence: evidence) == expected, "\(name)")
    }
}

@Test
func xcresultReconciliationRequiresExitStatusCountsAndFailureRecordsToAgree() throws {
    let zero = EvidenceCount.zero
    let one = try EvidenceCount.nonnegative(1)
    let two = try EvidenceCount.nonnegative(2)
    let maximum = try EvidenceCount.nonnegative(Int.max)
    let rows: [(String, Int32, TestResultEvidence, TestResultReconciliation)] = [
        ("clean pass", 0, .xcresult(status: .passed, total: one, passed: one, failed: zero, skipped: zero, expectedFailures: zero, failureRecords: zero), .passed(one)),
        ("clean failure", 65, .xcresult(status: .failed, total: one, passed: zero, failed: one, skipped: zero, expectedFailures: zero, failureRecords: one), .failed(one)),
        ("expected failure", 0, .xcresult(status: .expectedFailure, total: one, passed: zero, failed: zero, skipped: zero, expectedFailures: one, failureRecords: zero), .apparatus(.expectedFailures)),
        ("passed with expected failure", 0, .xcresult(status: .passed, total: one, passed: zero, failed: zero, skipped: zero, expectedFailures: one, failureRecords: zero), .apparatus(.expectedFailures)),
        ("failed with zero exit", 0, .xcresult(status: .failed, total: one, passed: zero, failed: one, skipped: zero, expectedFailures: zero, failureRecords: one), .apparatus(.exitDisagreement)),
        ("passed with nonzero exit", 65, .xcresult(status: .passed, total: one, passed: one, failed: zero, skipped: zero, expectedFailures: zero, failureRecords: zero), .apparatus(.exitDisagreement)),
        ("passed status with failure", 65, .xcresult(status: .passed, total: one, passed: zero, failed: one, skipped: zero, expectedFailures: zero, failureRecords: one), .apparatus(.inconsistentStatus)),
        ("failed status without failed case", 65, .xcresult(status: .failed, total: one, passed: one, failed: zero, skipped: zero, expectedFailures: zero, failureRecords: zero), .apparatus(.inconsistentStatus)),
        ("failure record without failed case", 65, .xcresult(status: .failed, total: one, passed: one, failed: zero, skipped: zero, expectedFailures: zero, failureRecords: one), .apparatus(.failureRecords)),
        ("failed case without record", 65, .xcresult(status: .failed, total: one, passed: zero, failed: one, skipped: zero, expectedFailures: zero, failureRecords: zero), .apparatus(.failureRecords)),
        ("partial skip", 0, .xcresult(status: .passed, total: two, passed: one, failed: zero, skipped: one, expectedFailures: zero, failureRecords: zero), .apparatus(.skippedCases)),
        ("skipped status", 0, .xcresult(status: .skipped, total: one, passed: one, failed: zero, skipped: zero, expectedFailures: zero, failureRecords: zero), .apparatus(.skippedCases)),
        ("unknown status", 0, .xcresult(status: .unknown, total: one, passed: one, failed: zero, skipped: zero, expectedFailures: zero, failureRecords: zero), .apparatus(.unknownStatus)),
        ("missing expected failures", 0, .xcresult(status: .expectedFailure, total: one, passed: one, failed: zero, skipped: zero, expectedFailures: zero, failureRecords: zero), .apparatus(.inconsistentStatus)),
        ("total mismatch", 0, .xcresult(status: .passed, total: two, passed: one, failed: zero, skipped: zero, expectedFailures: zero, failureRecords: zero), .apparatus(.inconsistentCounts)),
        ("zero executable cases", 0, .xcresult(status: .passed, total: zero, passed: zero, failed: zero, skipped: zero, expectedFailures: zero, failureRecords: zero), .apparatus(.noExecutedTests)),
        ("count overflow", 65, .xcresult(status: .failed, total: maximum, passed: maximum, failed: one, skipped: zero, expectedFailures: zero, failureRecords: one), .apparatus(.inconsistentCounts)),
    ]
    for (name, exitCode, evidence, expected) in rows {
        #expect(TestResultReconciler.reconcile(exitCode: exitCode, evidence: evidence) == expected, "\(name)")
    }
}
