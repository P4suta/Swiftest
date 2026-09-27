import Foundation
@testable import SwiftestEngine
import SwiftestModel
import Testing

@Test
func worldCursorOracleCoversEveryHeterogeneousCoordinate() throws {
    let lines = try WorldCursorOracle.text().split(separator: "\n").map(String.init)
    guard lines.count == 52 else {
        Issue.record("world oracle did not emit 48 coordinates and three definition preimages")
        return
    }
    #expect(lines[0] == "world-cursor-count\t48")
    #expect(lines[1] == "world-cursor\t0\t0\t0\t0\t0\t0\t0")
    #expect(lines[2] == "world-cursor\t1\t0\t0\t0\t0\t1\t0")
    #expect(lines[3] == "world-cursor\t2\t0\t0\t0\t1\t0\t1")
    #expect(lines[5] == "world-cursor\t4\t0\t0\t1\t0\t0\t2")
    #expect(lines[9] == "world-cursor\t8\t0\t1\t0\t0\t0\t4")
    #expect(lines[25] == "world-cursor\t24\t1\t0\t0\t0\t0\t12")
    #expect(lines[48] == "world-cursor\t47\t1\t2\t1\t1\t1\t23")
    let trace = Array(lines[1...48])
    #expect(Set(trace).count == 48)
    for (ordinal, line) in trace.enumerated() {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
        #expect(fields.count == 8)
        #expect(fields[0] == "world-cursor")
        #expect(fields[1] == String(ordinal))
    }
    let baseline = lines[49].split(separator: "\t", omittingEmptySubsequences: false)
    let changedLocale = lines[50].split(separator: "\t", omittingEmptySubsequences: false)
    let changedMutantOrder = lines[51].split(separator: "\t", omittingEmptySubsequences: false)
    guard baseline.count == 3, changedLocale.count == 3, changedMutantOrder.count == 3 else {
        Issue.record("world definition preimage has missing fields")
        return
    }
    #expect(baseline[0] == "world-definition-preimage")
    #expect(baseline[1] == "baseline")
    #expect(changedLocale[1] == "locale-value")
    #expect(changedMutantOrder[1] == "mutant-order")
    #expect(baseline[2] != changedLocale[2])
    #expect(baseline[2] == changedMutantOrder[2])
}

@Test
func worldDefinitionOracleRejectsLaterIdentityMismatchAndTruncatedSequence() throws {
    let expected = try Digest.sha256(Data("expected".utf8))
    let unexpected = try Digest.sha256(Data("unexpected".utf8))
    let first = WorldID.baseWorld(definition: expected, ordinal: 0)
    let second = WorldID.baseWorld(definition: unexpected, ordinal: 1)
    #expect(throws: WorldCursorOracleError.definitionDigestMismatch(second)) {
        try WorldCursorOracle.requireDefinitionIDs(
            [first, second], expectedCount: 2, expectedDefinition: expected
        )
    }
    #expect(throws: WorldCursorOracleError.unexpectedCardinality) {
        try WorldCursorOracle.requireDefinitionIDs(
            [first], expectedCount: 2, expectedDefinition: expected
        )
    }
    #expect(throws: WorldCursorOracleError.unexpectedCardinality) {
        try WorldCursorOracle.requireDefinitionIDs(
            [WorldID](), expectedCount: 0, expectedDefinition: expected
        )
    }
}
