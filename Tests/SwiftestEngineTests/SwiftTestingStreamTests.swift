import Foundation
import SwiftestEngine
import Testing

private func testingEvent(
    _ kind: SwiftTestingEventKind,
    testID: SwiftTestingTestID? = nil,
    issue: SwiftTestingIssue? = nil,
    iteration: Int? = nil
) -> SwiftTestingRecord {
    .event(SwiftTestingEventRecord(
        kind: kind,
        testID: testID,
        issue: issue,
        secondsSince1970: 1,
        iteration: iteration
    ))
}

private func parameterizedRun(
    id: SwiftTestingTestID,
    cases: [SwiftTestingRecord]
) -> [SwiftTestingRecord] {
    [
        .test(SwiftTestingTestRecord(id: id, name: "cases(_:)", kind: .function(parameterized: true))),
        testingEvent(.runStarted),
        testingEvent(.testStarted, testID: id),
    ] + cases + [
        testingEvent(.testEnded, testID: id),
        testingEvent(.runEnded),
    ]
}

@Test
func parameterizedCasesRequireMatchedStartAndEndBeforeParentEnd() throws {
    let id = try SwiftTestingTestID.parse("Suite/cases(_:)")
    let complete = parameterizedRun(id: id, cases: [
        testingEvent(.testCaseStarted, testID: id, iteration: 1),
        testingEvent(.testCaseStarted, testID: id, iteration: 1),
        testingEvent(.testCaseEnded, testID: id, iteration: 1),
        testingEvent(.testCaseEnded, testID: id, iteration: 1),
    ])
    let summary = try StableTestingABI.summarize(complete)
    #expect(summary.discovered.rawValue == 1)
    #expect(summary.passed.rawValue == 1)

    let missingStart = parameterizedRun(id: id, cases: [
        testingEvent(.testCaseEnded, testID: id, iteration: 1),
    ])
    #expect(throws: SwiftTestingStreamError.invalidSequence("case end without start")) {
        try StableTestingABI.summarize(missingStart)
    }

    let missingEnd = parameterizedRun(id: id, cases: [
        testingEvent(.testCaseStarted, testID: id, iteration: 1),
    ])
    #expect(throws: SwiftTestingStreamError.invalidSequence("test end without start")) {
        try StableTestingABI.summarize(missingEnd)
    }

    let noCases = parameterizedRun(id: id, cases: [])
    #expect(throws: SwiftTestingStreamError.invalidSequence("parameterized test without case evidence")) {
        try StableTestingABI.summarize(noCases)
    }
}

@Test
func parameterizedCaseEventsRequireAnActiveDeclaredParentAndSameIteration() throws {
    let id = try SwiftTestingTestID.parse("Suite/cases(_:)")
    let foreign = try SwiftTestingTestID.parse("Suite/foreign(_:)")
    let foreignCase = parameterizedRun(id: id, cases: [
        testingEvent(.testCaseStarted, testID: foreign, iteration: 1),
    ])
    #expect(throws: SwiftTestingStreamError.invalidSequence("case event without active parent and iteration")) {
        try StableTestingABI.summarize(foreignCase)
    }

    let missingIteration = parameterizedRun(id: id, cases: [
        testingEvent(.testCaseStarted, testID: id),
    ])
    #expect(throws: SwiftTestingStreamError.invalidSequence("case event without active parent and iteration")) {
        try StableTestingABI.summarize(missingIteration)
    }

    let unmatchedIteration = parameterizedRun(id: id, cases: [
        testingEvent(.testCaseStarted, testID: id, iteration: 1),
        testingEvent(.testCaseEnded, testID: id, iteration: 2),
    ])
    #expect(throws: SwiftTestingStreamError.invalidSequence("case end without start")) {
        try StableTestingABI.summarize(unmatchedIteration)
    }
}

@Test
func cancelledCaseCannotBeCountedAsPassedAndMustStillEnd() throws {
    let id = try SwiftTestingTestID.parse("Suite/cases(_:)")
    let cancelled = parameterizedRun(id: id, cases: [
        testingEvent(.testCaseStarted, testID: id, iteration: 1),
        testingEvent(.testCaseCancelled, testID: id, iteration: 1),
        testingEvent(.testCaseEnded, testID: id, iteration: 1),
    ])
    let summary = try StableTestingABI.summarize(cancelled)
    #expect(summary.passed.rawValue == 0)
    #expect(summary.cancelled.rawValue == 1)

    let duplicateCancellation = parameterizedRun(id: id, cases: [
        testingEvent(.testCaseStarted, testID: id, iteration: 1),
        testingEvent(.testCaseCancelled, testID: id, iteration: 1),
        testingEvent(.testCaseCancelled, testID: id, iteration: 1),
        testingEvent(.testCaseEnded, testID: id, iteration: 1),
    ])
    #expect(throws: SwiftTestingStreamError.invalidSequence("case cancellation without unmarked active case")) {
        try StableTestingABI.summarize(duplicateCancellation)
    }

    let missingCaseEnd = parameterizedRun(id: id, cases: [
        testingEvent(.testCaseStarted, testID: id, iteration: 1),
        testingEvent(.testCaseCancelled, testID: id, iteration: 1),
    ])
    #expect(throws: SwiftTestingStreamError.invalidSequence("test end without start")) {
        try StableTestingABI.summarize(missingCaseEnd)
    }
}

@Test
func testCancellationNeedsStartAndEndAndFailureTakesPrecedence() throws {
    let id = try SwiftTestingTestID.parse("Suite/cases(_:)")
    let cancellation = parameterizedRun(id: id, cases: [
        testingEvent(.testCaseStarted, testID: id, iteration: 1),
        testingEvent(.testCaseEnded, testID: id, iteration: 1),
        testingEvent(.testCancelled, testID: id),
    ])
    let cancelled = try StableTestingABI.summarize(cancellation)
    #expect(cancelled.passed.rawValue == 0)
    #expect(cancelled.cancelled.rawValue == 1)

    let issue = SwiftTestingIssue(isKnown: false, isFailure: true, severity: "error")
    let failed = parameterizedRun(id: id, cases: [
        testingEvent(.testCaseStarted, testID: id, iteration: 1),
        testingEvent(.issueRecorded, testID: id, issue: issue, iteration: 1),
        testingEvent(.testCaseCancelled, testID: id, iteration: 1),
        testingEvent(.testCaseEnded, testID: id, iteration: 1),
    ])
    let failedSummary = try StableTestingABI.summarize(failed)
    #expect(failedSummary.failed.rawValue == 1)
    #expect(failedSummary.cancelled.rawValue == 0)
    #expect(failedSummary.passed.rawValue == 0)
}

@Test
func swiftTestingABIRejectsZeroIteration() throws {
    let event = """
    {"version":"6.4","kind":"event","payload":{"kind":"testCaseStarted","instant":{"absolute":1,"since1970":1},"messages":[],"testID":"Suite/cases(_:)","iteration":0}}
    """
    #expect(throws: SwiftTestingStreamError.invalidNumber("iteration")) {
        try StableTestingABI.decodeRecord(Data(event.utf8))
    }
}
