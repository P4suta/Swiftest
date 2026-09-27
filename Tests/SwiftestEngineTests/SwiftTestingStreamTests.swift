import Foundation
import SwiftestEngine
import Testing

private func testingEvent(
    _ event: SwiftTestingEvent,
    testID: SwiftTestingTestID? = nil,
    iteration: Int? = nil
) -> SwiftTestingRecord {
    .event(SwiftTestingEventRecord(
        event: event,
        testID: testID,
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
    let campaign = try StableTestingABI.summarizeCampaign(complete)
    #expect(campaign.parameterizedFunctions.rawValue == 1)
    #expect(campaign.startedCases.rawValue == 2)
    #expect(campaign.endedCases.rawValue == 2)

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
func swiftTestingCampaignClosesMultipleBundlesWithoutDuplicateOrMissingRuns() throws {
    let first = try SwiftTestingTestID.parse("FirstTests/one()")
    let second = try SwiftTestingTestID.parse("SecondTests/two()")
    let firstRun: [SwiftTestingRecord] = [
        .test(SwiftTestingTestRecord(id: first, name: "one()", kind: .function(parameterized: false))),
        testingEvent(.runStarted),
        testingEvent(.testStarted, testID: first),
        testingEvent(.testEnded, testID: first),
        testingEvent(.runEnded),
    ]
    let secondRun: [SwiftTestingRecord] = [
        .test(SwiftTestingTestRecord(id: second, name: "two()", kind: .function(parameterized: false))),
        testingEvent(.runStarted),
        testingEvent(.testStarted, testID: second),
        testingEvent(.testEnded, testID: second),
        testingEvent(.runEnded),
    ]
    let campaign = try StableTestingABI.summarizeCampaign(firstRun + secondRun)
    #expect(campaign.runs.rawValue == 2)
    #expect(campaign.discovered.rawValue == 2)
    #expect(campaign.passed.rawValue == 2)
    #expect(campaign.functionNames == ["one()", "two()"])
    #expect(throws: SwiftTestingStreamError.invalidSequence("duplicate test across runs")) {
        try StableTestingABI.summarizeCampaign(firstRun + firstRun)
    }
    #expect(throws: SwiftTestingStreamError.invalidSequence("unterminated run")) {
        try StableTestingABI.summarizeCampaign(firstRun + Array(secondRun.dropLast()))
    }
    #expect(throws: SwiftTestingStreamError.invalidSequence("missing or duplicate test start")) {
        try StableTestingABI.summarizeCampaign(firstRun + [
            testingEvent(.runStarted),
            testingEvent(.testStarted, testID: second),
            testingEvent(.runEnded),
        ])
    }
}

@Test
func swiftTestingABIAcceptsPinnedSixFourPatchVersion() throws {
    let record = Data("{\"version\":\"6.4.0\",\"kind\":\"test\",\"payload\":{\"kind\":\"function\",\"name\":\"one()\",\"id\":\"Module.one()\",\"isParameterized\":false,\"sourceLocation\":{\"filePath\":\"/tmp/One.swift\",\"line\":1,\"column\":1},\"tags\":[]}}".utf8)
    let decoded = try StableTestingABI.decodeRecord(record)
    if case .test(let test) = decoded {
        #expect(test.name == "one()")
    } else {
        Issue.record("pinned ABI test record was not decoded")
    }
    let unpinned = Data(String(decoding: record, as: UTF8.self)
        .replacingOccurrences(of: "6.4.0", with: "6.4").utf8)
    #expect(throws: SwiftTestingStreamError.unsupportedVersion("\"6.4\"")) {
        try StableTestingABI.decodeRecord(unpinned)
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
    #expect(throws: SwiftTestingStreamError.invalidSequence("event kind and locus disagree")) {
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
func nonparameterizedCaseEventsAndUnownedNonfailureIssuesAreRejected() throws {
    let id = try SwiftTestingTestID.parse("Suite/plain()")
    let foreign = try SwiftTestingTestID.parse("Suite/foreign()")
    let plain: [SwiftTestingRecord] = [
        .test(SwiftTestingTestRecord(id: id, name: "plain()", kind: .function(parameterized: false))),
        testingEvent(.runStarted),
        testingEvent(.testStarted, testID: id),
        testingEvent(.testCaseStarted, testID: id, iteration: 1),
        testingEvent(.testCaseEnded, testID: id, iteration: 1),
        testingEvent(.testEnded, testID: id),
        testingEvent(.runEnded),
    ]
    #expect(throws: SwiftTestingStreamError.invalidSequence("case event without active parent and iteration")) {
        try StableTestingABI.summarize(plain)
    }

    let nonfailure = SwiftTestingIssue(isKnown: true, isFailure: false, severity: "warning")
    let unknownIssue: [SwiftTestingRecord] = [
        .test(SwiftTestingTestRecord(id: id, name: "plain()", kind: .function(parameterized: false))),
        testingEvent(.runStarted),
        testingEvent(.testStarted, testID: id),
        testingEvent(.issueRecorded(nonfailure), testID: foreign),
        testingEvent(.testEnded, testID: id),
        testingEvent(.runEnded),
    ]
    #expect(throws: SwiftTestingStreamError.invalidSequence("issue outside active test")) {
        try StableTestingABI.summarize(unknownIssue)
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
        testingEvent(.issueRecorded(issue), testID: id, iteration: 1),
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
    {"version":"6.4.0","kind":"event","payload":{"kind":"testCaseStarted","instant":{"absolute":1,"since1970":1},"messages":[],"testID":"Suite/cases(_:)","iteration":0}}
    """
    #expect(throws: SwiftTestingStreamError.invalidNumber("iteration")) {
        try StableTestingABI.decodeRecord(Data(event.utf8))
    }
}

@Test
func swiftTestingAttachmentPathsRejectAmbiguousLocations() throws {
    let path = try SwiftTestingAttachmentPath.parse("/private/tmp/evidence/world.json")
    #expect(path.rawValue == "/private/tmp/evidence/world.json")
    for invalid in ["world.json", "/", "/private//world.json", "/private/./world.json", "/private/../world.json", "/private/world\0.json"] {
        #expect(throws: SwiftTestingStreamError.invalidIdentifier("attachment path")) {
            try SwiftTestingAttachmentPath.parse(invalid)
        }
    }
}

@Test
func swiftTestingAttachmentEventsRetainTypedPathAndActiveTestIdentity() throws {
    let test = """
    {"version":"6.4.0","kind":"test","payload":{"kind":"function","name":"one()","id":"Module.one()","isParameterized":false,"sourceLocation":{"filePath":"/tmp/One.swift","line":1,"column":1},"tags":[]}}
    """
    let started = """
    {"version":"6.4.0","kind":"event","payload":{"kind":"runStarted","instant":{"absolute":1,"since1970":1},"messages":[]}}
    {"version":"6.4.0","kind":"event","payload":{"kind":"testStarted","instant":{"absolute":1,"since1970":1},"messages":[],"testID":"Module.one()"}}
    """
    let attached = """
    {"version":"6.4.0","kind":"event","payload":{"kind":"valueAttached","instant":{"absolute":1,"since1970":1},"messages":[],"testID":"Module.one()","attachment":{"path":"/private/tmp/evidence/world.json"}}}
    """
    let testEnded = """
    {"version":"6.4.0","kind":"event","payload":{"kind":"testEnded","instant":{"absolute":1,"since1970":1},"messages":[],"testID":"Module.one()"}}
    """
    let runEnded = """
    {"version":"6.4.0","kind":"event","payload":{"kind":"runEnded","instant":{"absolute":1,"since1970":1},"messages":[]}}
    """
    let bytes = Data(([test, started, attached, testEnded, runEnded].joined(separator: "\n") + "\n").utf8)
    let evidence = try SwiftTestingCampaignEvidence.decode(bytes)
    #expect(evidence.summary.passed.rawValue == 1)
    #expect(evidence.attachments.count == 1)
    #expect(evidence.attachments.first?.testID?.rawValue == "Module.one()")
    #expect(evidence.attachments.first?.path.rawValue == "/private/tmp/evidence/world.json")

    let afterEnd = Data(([test, started, testEnded, attached, runEnded].joined(separator: "\n") + "\n").utf8)
    #expect(throws: SwiftTestingStreamError.invalidSequence("attachment outside active test")) {
        try SwiftTestingCampaignEvidence.decode(afterEnd)
    }
    let noOwner = attached.replacingOccurrences(of: ",\"testID\":\"Module.one()\"", with: "")
        .replacingOccurrences(of: "\"attachment\":", with: "\"iteration\":1,\"attachment\":")
    #expect(noOwner != attached)
    let unowned = Data(([test, started, noOwner, testEnded, runEnded].joined(separator: "\n") + "\n").utf8)
    #expect(throws: SwiftTestingStreamError.invalidSequence("invalid event locus")) {
        try SwiftTestingCampaignEvidence.decode(unowned)
    }
}

@Test
func swiftTestingScopedEventsRequireActiveCaseAndLegalEventLocus() throws {
    let id = try SwiftTestingTestID.parse("Suite/cases(_:)")
    let path = try SwiftTestingAttachmentPath.parse("/private/tmp/evidence/case.json")
    let issue = SwiftTestingIssue(isKnown: false, isFailure: true, severity: "error")
    let active = parameterizedRun(id: id, cases: [
        testingEvent(.testCaseStarted, testID: id, iteration: 1),
        testingEvent(.valueAttached(path), testID: id, iteration: 1),
        testingEvent(.testCaseEnded, testID: id, iteration: 1),
    ])
    #expect(try StableTestingABI.summarize(active).passed.rawValue == 1)

    let repeatedTestLifecycle: [SwiftTestingRecord] = [
        .test(SwiftTestingTestRecord(id: id, name: "cases(_:)", kind: .function(parameterized: true))),
        testingEvent(.runStarted),
        testingEvent(.testStarted, testID: id, iteration: 1),
        testingEvent(.testCaseStarted, testID: id, iteration: 1),
        testingEvent(.testCaseEnded, testID: id, iteration: 1),
        testingEvent(.testEnded, testID: id, iteration: 1),
        testingEvent(.runEnded),
    ]
    #expect(try StableTestingABI.summarize(repeatedTestLifecycle).passed.rawValue == 1)

    let crossedRepetition: [SwiftTestingRecord] = [
        .test(SwiftTestingTestRecord(id: id, name: "cases(_:)", kind: .function(parameterized: true))),
        testingEvent(.runStarted),
        testingEvent(.testStarted, testID: id, iteration: 1),
        testingEvent(.testCaseStarted, testID: id, iteration: 1),
        testingEvent(.testCaseEnded, testID: id, iteration: 1),
        testingEvent(.testEnded, testID: id, iteration: 2),
        testingEvent(.runEnded),
    ]
    #expect(throws: SwiftTestingStreamError.invalidSequence("test end without start")) {
        try StableTestingABI.summarize(crossedRepetition)
    }

    let crossedCaseRepetition: [SwiftTestingRecord] = [
        .test(SwiftTestingTestRecord(id: id, name: "cases(_:)", kind: .function(parameterized: true))),
        testingEvent(.runStarted),
        testingEvent(.testStarted, testID: id, iteration: 1),
        testingEvent(.testCaseStarted, testID: id, iteration: 2),
        testingEvent(.testCaseEnded, testID: id, iteration: 2),
        testingEvent(.testEnded, testID: id, iteration: 1),
        testingEvent(.runEnded),
    ]
    #expect(throws: SwiftTestingStreamError.invalidSequence("case repetition disagrees with parent test")) {
        try StableTestingABI.summarize(crossedCaseRepetition)
    }

    let afterCaseEnd = parameterizedRun(id: id, cases: [
        testingEvent(.testCaseStarted, testID: id, iteration: 1),
        testingEvent(.testCaseEnded, testID: id, iteration: 1),
        testingEvent(.valueAttached(path), testID: id, iteration: 1),
    ])
    #expect(throws: SwiftTestingStreamError.invalidSequence("attachment outside active test case")) {
        try StableTestingABI.summarize(afterCaseEnd)
    }
    let beforeCaseStart = parameterizedRun(id: id, cases: [
        testingEvent(.issueRecorded(issue), testID: id, iteration: 1),
        testingEvent(.testCaseStarted, testID: id, iteration: 1),
        testingEvent(.testCaseEnded, testID: id, iteration: 1),
    ])
    #expect(throws: SwiftTestingStreamError.invalidSequence("issue outside active test case")) {
        try StableTestingABI.summarize(beforeCaseStart)
    }
    let afterCaseIssue = parameterizedRun(id: id, cases: [
        testingEvent(.testCaseStarted, testID: id, iteration: 1),
        testingEvent(.testCaseEnded, testID: id, iteration: 1),
        testingEvent(.issueRecorded(issue), testID: id, iteration: 1),
    ])
    #expect(throws: SwiftTestingStreamError.invalidSequence("issue outside active test case")) {
        try StableTestingABI.summarize(afterCaseIssue)
    }

    let malformedRun: [SwiftTestingRecord] = [
        .test(SwiftTestingTestRecord(id: id, name: "cases(_:)", kind: .function(parameterized: true))),
        testingEvent(.runStarted, testID: id),
    ]
    #expect(throws: SwiftTestingStreamError.invalidSequence("event kind and locus disagree")) {
        try StableTestingABI.summarize(malformedRun)
    }
    let malformedTest = parameterizedRun(id: id, cases: [
        testingEvent(.testStarted, iteration: 1),
    ])
    #expect(throws: SwiftTestingStreamError.invalidSequence("invalid event locus")) {
        try StableTestingABI.summarize(malformedTest)
    }
}
