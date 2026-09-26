import Foundation
import SwiftestCodec
import SwiftestModel

public enum XCResultSummaryError: Error, Equatable, Sendable {
    case codec(StrictJSONError)
    case invalidStatus(String)
    case negativeCount(String)
    case countOverflow
    case inconsistentTotals
    case inconsistentStatus
    case invalidTimestamp(String)
    case count(NumericValueError)
}

public enum XCResultStatus: String, CaseIterable, Sendable {
    case passed = "Passed"
    case failed = "Failed"
    case skipped = "Skipped"
    case expectedFailure = "Expected Failure"
    case unknown
}

public struct XCResultSummary: Equatable, Sendable {
    public let result: XCResultStatus
    public let total: EvidenceCount
    public let passed: EvidenceCount
    public let failed: EvidenceCount
    public let skipped: EvidenceCount
    public let expectedFailures: EvidenceCount
    public let failureRecords: EvidenceCount
    public let runtimeWarnings: EvidenceCount

    public init(
        result: XCResultStatus,
        total: EvidenceCount,
        passed: EvidenceCount,
        failed: EvidenceCount,
        skipped: EvidenceCount,
        expectedFailures: EvidenceCount,
        failureRecords: EvidenceCount,
        runtimeWarnings: EvidenceCount
    ) {
        self.result = result
        self.total = total
        self.passed = passed
        self.failed = failed
        self.skipped = skipped
        self.expectedFailures = expectedFailures
        self.failureRecords = failureRecords
        self.runtimeWarnings = runtimeWarnings
    }

    public static func decode(_ data: Data) throws(XCResultSummaryError) -> XCResultSummary {
        let document: JSONValue
        do {
            document = try StrictJSON.decode(data)
        } catch let error {
            throw .codec(error)
        }
        let fields = try object(document)
        var reader = try codecObject(document)
        try expectString(&reader, "title")
        try expectString(&reader, "environmentDescription")
        let statusText = try string(&reader, "result")
        guard let status = XCResultStatus(rawValue: statusText), status != .unknown else {
            throw .invalidStatus(statusText)
        }
        let total = try count(&reader, "totalTestCount")
        let passed = try count(&reader, "passedTests")
        let failed = try count(&reader, "failedTests")
        let skipped = try count(&reader, "skippedTests")
        let expected = try count(&reader, "expectedFailures")
        let insights = try array(&reader, "topInsights")
        let statistics = try array(&reader, "statistics")
        let devices = try value(&reader, "devicesAndConfigurations")
        let failures = try array(&reader, "testFailures")
        let warnings = try array(&reader, "runtimeWarnings")
        for insight in insights {
            try validateInsight(insight)
        }
        for statistic in statistics {
            try validateStatistic(statistic)
        }
        let deviceCounts = try validateDeviceConfiguration(devices)
        if deviceCounts.passed != passed || deviceCounts.failed != failed
            || deviceCounts.skipped != skipped || deviceCounts.expectedFailures != expected {
            throw .inconsistentTotals
        }
        for failure in failures {
            try validateFailure(failure)
        }
        for warning in warnings {
            try validateWarning(warning)
        }
        let startTime: Double?
        if fields["startTime"] != nil {
            startTime = try timestamp(try value(&reader, "startTime"), name: "startTime")
        } else {
            startTime = nil
        }
        let finishTime: Double?
        if fields["finishTime"] != nil {
            finishTime = try timestamp(try value(&reader, "finishTime"), name: "finishTime")
        } else {
            finishTime = nil
        }
        if let startTime, let finishTime, finishTime < startTime {
            throw .invalidTimestamp("finishTime")
        }
        try finish(reader)
        let first = passed.rawValue.addingReportingOverflow(failed.rawValue)
        let second = first.partialValue.addingReportingOverflow(skipped.rawValue)
        let third = second.partialValue.addingReportingOverflow(expected.rawValue)
        if first.overflow || second.overflow || third.overflow {
            throw .countOverflow
        }
        if total.rawValue != third.partialValue {
            throw .inconsistentTotals
        }
        switch status {
        case .passed:
            if failed.rawValue > 0 || !failures.isEmpty {
                throw .inconsistentStatus
            }
        case .failed:
            if failed.rawValue == 0 && failures.isEmpty {
                throw .inconsistentStatus
            }
        case .skipped:
            if skipped.rawValue == 0 {
                throw .inconsistentStatus
            }
        case .expectedFailure:
            if expected.rawValue == 0 {
                throw .inconsistentStatus
            }
        case .unknown:
            throw .invalidStatus(statusText)
        }
        let failureRecords: EvidenceCount
        let runtimeWarnings: EvidenceCount
        do {
            failureRecords = try .nonnegative(failures.count)
            runtimeWarnings = try .nonnegative(warnings.count)
        } catch let error {
            throw .count(error)
        }
        return XCResultSummary(
            result: status,
            total: total,
            passed: passed,
            failed: failed,
            skipped: skipped,
            expectedFailures: expected,
            failureRecords: failureRecords,
            runtimeWarnings: runtimeWarnings
        )
    }

    private static func validateInsight(_ input: JSONValue) throws(XCResultSummaryError) {
        var reader = try codecObject(input)
        try expectString(&reader, "impact")
        try expectString(&reader, "category")
        try expectString(&reader, "text")
        try finish(reader)
    }

    private static func validateStatistic(_ input: JSONValue) throws(XCResultSummaryError) {
        var reader = try codecObject(input)
        try expectString(&reader, "title")
        try expectString(&reader, "subtitle")
        try finish(reader)
    }

    private struct DeviceCounts {
        let passed: EvidenceCount
        let failed: EvidenceCount
        let skipped: EvidenceCount
        let expectedFailures: EvidenceCount
    }

    private static func validateDeviceConfiguration(
        _ input: JSONValue
    ) throws(XCResultSummaryError) -> DeviceCounts {
        var reader = try codecObject(input)
        try validateDevice(try value(&reader, "device"))
        try validateConfiguration(try value(&reader, "testPlanConfiguration"))
        let passed = try count(&reader, "passedTests")
        let failed = try count(&reader, "failedTests")
        let skipped = try count(&reader, "skippedTests")
        let expected = try count(&reader, "expectedFailures")
        try finish(reader)
        return DeviceCounts(
            passed: passed,
            failed: failed,
            skipped: skipped,
            expectedFailures: expected
        )
    }

    private static func validateDevice(_ input: JSONValue) throws(XCResultSummaryError) {
        let fields = try object(input)
        var reader = try codecObject(input)
        for key in ["deviceId", "deviceName", "architecture", "modelName", "platform", "osVersion"] {
            try expectString(&reader, key)
        }
        if fields["osBuildNumber"] != nil {
            try expectString(&reader, "osBuildNumber")
        }
        try finish(reader)
    }

    private static func validateConfiguration(_ input: JSONValue) throws(XCResultSummaryError) {
        var reader = try codecObject(input)
        try expectString(&reader, "configurationId")
        try expectString(&reader, "configurationName")
        try finish(reader)
    }

    private static func validateFailure(_ input: JSONValue) throws(XCResultSummaryError) {
        let fields = try object(input)
        var reader = try codecObject(input)
        for key in ["testName", "targetName", "failureText", "testIdentifierString"] {
            try expectString(&reader, key)
        }
        let identifier = try value(&reader, "testIdentifier")
        guard case .number(let digits) = identifier, Int(digits) != nil else {
            throw .codec(.expectedInteger("testIdentifier"))
        }
        if fields["testIdentifierURL"] != nil {
            try expectString(&reader, "testIdentifierURL")
        }
        try finish(reader)
    }

    private static func validateWarning(_ input: JSONValue) throws(XCResultSummaryError) {
        let fields = try object(input)
        var reader = try codecObject(input)
        try expectString(&reader, "issueType")
        try expectString(&reader, "message")
        for key in ["targetName", "sourceURL", "className"] where fields[key] != nil {
            try expectString(&reader, key)
        }
        try finish(reader)
    }

    private static func timestamp(
        _ input: JSONValue,
        name: String
    ) throws(XCResultSummaryError) -> Double {
        guard case .number(let text) = input,
            let number = Double(text), number.isFinite, number >= 0 else {
            throw .invalidTimestamp(name)
        }
        return number
    }

    private static func count(
        _ reader: inout JSONObjectReader,
        _ key: String
    ) throws(XCResultSummaryError) -> EvidenceCount {
        let raw = try integer(&reader, key)
        if raw < 0 {
            throw .negativeCount(key)
        }
        do {
            return try .nonnegative(raw)
        } catch let error {
            throw .count(error)
        }
    }

    private static func object(_ input: JSONValue) throws(XCResultSummaryError) -> [String: JSONValue] {
        guard case .object(let fields) = input else {
            throw .codec(.expectedObject)
        }
        return fields
    }

    private static func codecObject(_ input: JSONValue) throws(XCResultSummaryError) -> JSONObjectReader {
        do {
            return try JSONObjectReader(input)
        } catch let error {
            throw .codec(error)
        }
    }

    private static func string(
        _ reader: inout JSONObjectReader,
        _ key: String
    ) throws(XCResultSummaryError) -> String {
        do {
            return try reader.requiredString(key)
        } catch let error {
            throw .codec(error)
        }
    }

    private static func expectString(
        _ reader: inout JSONObjectReader,
        _ key: String
    ) throws(XCResultSummaryError) {
        let value = try value(&reader, key)
        guard case .string = value else {
            throw .codec(.expectedString(key))
        }
    }

    private static func integer(
        _ reader: inout JSONObjectReader,
        _ key: String
    ) throws(XCResultSummaryError) -> Int {
        do {
            return try reader.requiredInteger(key)
        } catch let error {
            throw .codec(error)
        }
    }

    private static func array(
        _ reader: inout JSONObjectReader,
        _ key: String
    ) throws(XCResultSummaryError) -> [JSONValue] {
        do {
            return try reader.requiredArray(key)
        } catch let error {
            throw .codec(error)
        }
    }

    private static func value(
        _ reader: inout JSONObjectReader,
        _ key: String
    ) throws(XCResultSummaryError) -> JSONValue {
        do {
            return try reader.requiredValue(key)
        } catch let error {
            throw .codec(error)
        }
    }

    private static func finish(_ reader: JSONObjectReader) throws(XCResultSummaryError) {
        do {
            try reader.finish()
        } catch let error {
            throw .codec(error)
        }
    }
}
