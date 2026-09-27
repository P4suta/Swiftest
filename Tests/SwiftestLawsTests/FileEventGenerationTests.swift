import SwiftestModel
@testable import SwiftestPlatform
import Testing

@Test
func repeatedAttributeEventsAdvanceWitnessAfterContinuitySaturates() throws {
    let initial = FileEventWitness.initial
    guard let first = initial.recordingAttributeEvent(),
        let second = first.recordingAttributeEvent() else {
        Issue.record("event generation overflowed after two observations")
        return
    }
    #expect(initial.continuity == .eventFree)
    #expect(first.continuity == .attributeAmbiguous)
    #expect(second.continuity == .attributeAmbiguous)
    #expect(first != second)
    #expect(first.generation != second.generation)
    #expect(first.including(.eventFree) == first)
}

@Test
func attributeEventHealthRetainsFirstWatchedPath() throws {
    guard let firstPath = WatchedPath.validated("/private/tmp/First.swift"),
        let secondPath = WatchedPath.validated("/private/tmp/Second.swift") else {
        Issue.record("valid absolute watched paths were rejected")
        return
    }
    #expect(WatchedPath.validated("relative.swift") == nil)
    #expect(WatchedPath.validated("/private/tmp/Trailing/") == nil)
    #expect(WatchedPath.validated("/private/tmp/../Escaped.swift") == nil)
    #expect(WatchedPath.validated("/private/tmp/./Aliased.swift") == nil)
    #expect(WatchedPath.validated("/private//tmp/Aliased.swift") == nil)
    #expect(WatchedPath.validated("/") == nil)
    try FileEventHealth.initial.requireEventFree()
    #expect(throws: PlatformError.attributeOriginMissing) {
        try FileEventHealth.initial.including(.attributeAmbiguous).requireEventFree()
    }
    guard let first = FileEventHealth.initial.advanceForAttribute(at: firstPath),
        let second = first.advanceForAttribute(at: secondPath) else {
        Issue.record("attribute event generation overflowed")
        return
    }
    #expect(first.firstAttributePath == firstPath)
    #expect(second.firstAttributePath == firstPath)
    #expect(first.witness.generation != second.witness.generation)
    #expect(first.including(.attributeAmbiguous).firstAttributePath == firstPath)
    #expect(second.including(.eventFree) == second)
    #expect(throws: PlatformError.attributeAmbiguous(firstPath)) {
        try first.requireEventFree()
    }
    #expect(throws: PlatformError.attributeAmbiguous(firstPath)) {
        try second.requireEventFree()
    }
}
