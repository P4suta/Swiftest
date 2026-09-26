import Foundation
import SwiftestCodec
import SwiftestModel

public enum SwiftTestingStreamError: Error, Equatable, Sendable {
    case codec(StrictJSONError)
    case emptyStream
    case missingTerminalNewline
    case emptyLine(Int)
    case unsupportedVersion(String)
    case invalidRecordKind(String)
    case invalidTestKind(String)
    case invalidEventKind(String)
    case invalidMessageSymbol(String)
    case invalidIdentifier(String)
    case invalidNumber(String)
    case invalidEventPayload(String)
    case invalidSequence(String)
    case count(NumericValueError)
}

public struct SwiftTestingTestID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    private init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func parse(_ value: String) throws(SwiftTestingStreamError) -> SwiftTestingTestID {
        if value.isEmpty || value.utf8.contains(0) {
            throw .invalidIdentifier("testID")
        }
        return SwiftTestingTestID(rawValue: value)
    }

    public var description: String { rawValue }
}

public enum SwiftTestingTestKind: Equatable, Sendable {
    case suite
    case function(parameterized: Bool)
}

public struct SwiftTestingTestRecord: Equatable, Sendable {
    public let id: SwiftTestingTestID
    public let name: String
    public let kind: SwiftTestingTestKind

    public init(id: SwiftTestingTestID, name: String, kind: SwiftTestingTestKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

public enum SwiftTestingEventKind: String, CaseIterable, Sendable {
    case runStarted
    case testStarted
    case testCaseStarted
    case issueRecorded
    case testCaseEnded
    case testEnded
    case testSkipped
    case runEnded
    case valueAttached
    case testCancelled
    case testCaseCancelled
}

public struct SwiftTestingIssue: Equatable, Sendable {
    public let isKnown: Bool
    public let isFailure: Bool
    public let severity: String

    public init(isKnown: Bool, isFailure: Bool, severity: String) {
        self.isKnown = isKnown
        self.isFailure = isFailure
        self.severity = severity
    }
}

public struct SwiftTestingEventRecord: Equatable, Sendable {
    public let kind: SwiftTestingEventKind
    public let testID: SwiftTestingTestID?
    public let issue: SwiftTestingIssue?
    public let secondsSince1970: Double
    public let iteration: Int?

    public init(
        kind: SwiftTestingEventKind,
        testID: SwiftTestingTestID?,
        issue: SwiftTestingIssue?,
        secondsSince1970: Double,
        iteration: Int? = nil
    ) {
        self.kind = kind
        self.testID = testID
        self.issue = issue
        self.secondsSince1970 = secondsSince1970
        self.iteration = iteration
    }
}

public enum SwiftTestingRecord: Equatable, Sendable {
    case test(SwiftTestingTestRecord)
    case event(SwiftTestingEventRecord)
}

public struct SwiftTestingRunSummary: Equatable, Sendable {
    public let discovered: EvidenceCount
    public let passed: EvidenceCount
    public let failed: EvidenceCount
    public let skipped: EvidenceCount
    public let cancelled: EvidenceCount
    public let runIssues: EvidenceCount

    public init(
        discovered: EvidenceCount,
        passed: EvidenceCount,
        failed: EvidenceCount,
        skipped: EvidenceCount,
        cancelled: EvidenceCount,
        runIssues: EvidenceCount
    ) {
        self.discovered = discovered
        self.passed = passed
        self.failed = failed
        self.skipped = skipped
        self.cancelled = cancelled
        self.runIssues = runIssues
    }
}

private struct SwiftTestingCaseGroup: Hashable {
    let testID: SwiftTestingTestID
    let iteration: Int
}

private struct SwiftTestingCaseProgress {
    var started = 0
    var ended = 0
    var cancellationMarkers = 0

    var active: Int { started - ended }
}

extension StableTestingABI {
    public static func decodeStream(_ data: Data) throws(SwiftTestingStreamError) -> [SwiftTestingRecord] {
        if data.isEmpty {
            throw .emptyStream
        }
        if data.last != 10 {
            throw .missingTerminalNewline
        }
        let lines = data.split(separator: 10, omittingEmptySubsequences: false)
        var records: [SwiftTestingRecord] = []
        for (index, line) in lines.dropLast().enumerated() {
            if line.isEmpty {
                throw .emptyLine(index + 1)
            }
            records.append(try decodeRecord(Data(line)))
        }
        return records
    }

    public static func decodeRecord(_ data: Data) throws(SwiftTestingStreamError) -> SwiftTestingRecord {
        let value: JSONValue
        do {
            value = try StrictJSON.decode(data)
        } catch let error {
            throw .codec(error)
        }
        var reader: JSONObjectReader
        do {
            reader = try JSONObjectReader(value)
        } catch let error {
            throw .codec(error)
        }
        let version: JSONValue
        let kind: String
        let payload: JSONValue
        do {
            version = try reader.requiredValue("version")
            kind = try reader.requiredString("kind")
            payload = try reader.requiredValue("payload")
            try reader.finish()
        } catch let error {
            throw .codec(error)
        }
        guard version == .string("6.4") else {
            throw .unsupportedVersion(StrictJSON.render(version))
        }
        switch kind {
        case "test":
            return .test(try decodeTest(payload))
        case "event":
            return .event(try decodeEventRecord(payload))
        default:
            throw .invalidRecordKind(kind)
        }
    }

    public static func summarize(
        _ records: [SwiftTestingRecord]
    ) throws(SwiftTestingStreamError) -> SwiftTestingRunSummary {
        var discovered: [SwiftTestingTestID: SwiftTestingTestKind] = [:]
        var functions = Set<SwiftTestingTestID>()
        var started = Set<SwiftTestingTestID>()
        var completed = Set<SwiftTestingTestID>()
        var skipped = Set<SwiftTestingTestID>()
        var cancellationMarkers = Set<SwiftTestingTestID>()
        var caseCancellationMarkers = Set<SwiftTestingTestID>()
        var caseProgress: [SwiftTestingCaseGroup: SwiftTestingCaseProgress] = [:]
        var failing = Set<SwiftTestingTestID>()
        var runIssues = 0
        var runStarted = false
        var runEnded = false
        for record in records {
            switch record {
            case .test(let test):
                if runEnded || discovered.updateValue(test.kind, forKey: test.id) != nil {
                    throw .invalidSequence("duplicate or late test declaration")
                }
                if case .function = test.kind {
                    functions.insert(test.id)
                }
            case .event(let event):
                if runEnded {
                    throw .invalidSequence("event after run end")
                }
                if event.kind == .runStarted {
                    if runStarted {
                        throw .invalidSequence("duplicate run start")
                    }
                    runStarted = true
                    continue
                }
                if !runStarted {
                    throw .invalidSequence("event before run start")
                }
                if event.kind == .runEnded {
                    runEnded = true
                    continue
                }
                if event.kind == .issueRecorded, let issue = event.issue, issue.isFailure {
                    if let id = event.testID {
                        guard discovered[id] != nil, started.contains(id), !completed.contains(id) else {
                            throw .invalidSequence("issue outside active test")
                        }
                        failing.insert(id)
                    } else {
                        runIssues += 1
                    }
                }
                switch event.kind {
                case .testStarted:
                    guard let id = event.testID, discovered[id] != nil,
                        !skipped.contains(id), started.insert(id).inserted else {
                        throw .invalidSequence("missing or duplicate test start")
                    }
                case .testEnded:
                    guard let id = event.testID,
                        started.contains(id),
                        !caseProgress.contains(where: { $0.key.testID == id && $0.value.active != 0 }),
                        completed.insert(id).inserted else {
                        throw .invalidSequence("test end without start")
                    }
                    if case .function(parameterized: true) = discovered[id],
                        !caseProgress.contains(where: { $0.key.testID == id && $0.value.started > 0 }) {
                        throw .invalidSequence("parameterized test without case evidence")
                    }
                case .testSkipped:
                    guard let id = event.testID, discovered[id] != nil,
                        !started.contains(id), skipped.insert(id).inserted else {
                        throw .invalidSequence("missing or duplicate test skip")
                    }
                case .testCancelled:
                    guard let id = event.testID, started.contains(id),
                        !completed.contains(id), cancellationMarkers.insert(id).inserted else {
                        throw .invalidSequence("missing or duplicate test cancellation")
                    }
                case .testCaseStarted, .testCaseEnded, .testCaseCancelled:
                    guard let id = event.testID, functions.contains(id),
                        started.contains(id), !completed.contains(id),
                        let iteration = event.iteration, iteration > 0 else {
                        throw .invalidSequence("case event without active parent and iteration")
                    }
                    let group = SwiftTestingCaseGroup(testID: id, iteration: iteration)
                    var progress: SwiftTestingCaseProgress
                    if let prior = caseProgress[group] {
                        progress = prior
                    } else {
                        progress = SwiftTestingCaseProgress()
                    }
                    switch event.kind {
                    case .testCaseStarted:
                        progress.started += 1
                    case .testCaseEnded:
                        guard progress.active > 0 else {
                            throw .invalidSequence("case end without start")
                        }
                        progress.ended += 1
                    case .testCaseCancelled:
                        let unpairedMarkers = max(0, progress.cancellationMarkers - progress.ended)
                        guard progress.active > unpairedMarkers else {
                            throw .invalidSequence("case cancellation without unmarked active case")
                        }
                        progress.cancellationMarkers += 1
                        caseCancellationMarkers.insert(id)
                    default:
                        throw .invalidSequence("unexpected case event")
                    }
                    caseProgress[group] = progress
                case .runStarted, .runEnded, .issueRecorded, .valueAttached:
                    break
                }
            }
        }
        if !runStarted || !runEnded {
            throw .invalidSequence("incomplete run")
        }
        if !started.isSubset(of: completed) {
            throw .invalidSequence("unterminated test")
        }
        let terminal = completed.union(skipped)
        if !terminal.isSubset(of: Set(discovered.keys)) {
            throw .invalidSequence("result for undeclared test")
        }
        if !failing.isSubset(of: functions) {
            throw .invalidSequence("failure for undeclared test")
        }
        if !functions.isSubset(of: terminal) {
            throw .invalidSequence("discovered test without result")
        }
        if !completed.isDisjoint(with: skipped) {
            throw .invalidSequence("conflicting test results")
        }
        if caseProgress.values.contains(where: { $0.active != 0 || $0.cancellationMarkers > $0.ended }) {
            throw .invalidSequence("unterminated or unaccounted test case")
        }
        let failed = completed.intersection(failing)
        let cancelled = completed.intersection(functions)
            .intersection(cancellationMarkers.union(caseCancellationMarkers))
            .subtracting(failed)
        do {
            return try SwiftTestingRunSummary(
                discovered: .nonnegative(functions.count),
                passed: .nonnegative(completed.intersection(functions)
                    .subtracting(failed).subtracting(cancelled).count),
                failed: .nonnegative(failed.count),
                skipped: .nonnegative(skipped.intersection(functions).count),
                cancelled: .nonnegative(cancelled.count),
                runIssues: .nonnegative(runIssues)
            )
        } catch let error {
            throw .count(error)
        }
    }

    private static func decodeTest(
        _ value: JSONValue
    ) throws(SwiftTestingStreamError) -> SwiftTestingTestRecord {
        let fields = try objectFields(value)
        var reader = try codecObject(value)
        let kind = try codecString(&reader, "kind")
        let name = try codecString(&reader, "name")
        let id = try SwiftTestingTestID.parse(codecString(&reader, "id"))
        let location = try codecValue(&reader, "sourceLocation")
        try validateLocation(location)
        if fields["displayName"] != nil {
            let displayName = try codecString(&reader, "displayName")
            if displayName.isEmpty {
                throw .invalidIdentifier("displayName")
            }
        }
        if fields["tags"] != nil {
            let tags = try codecArray(&reader, "tags")
            for tag in tags {
                guard case .string = tag else {
                    throw .codec(.expectedString("tags"))
                }
            }
        }
        if fields["bugs"] != nil {
            let bugs = try codecArray(&reader, "bugs")
            for bug in bugs {
                try validateBug(bug)
            }
        }
        if fields["timeLimit"] != nil {
            try validateNumber(try codecValue(&reader, "timeLimit"), field: "timeLimit")
        }
        let shape: SwiftTestingTestKind
        switch kind {
        case "suite":
            shape = .suite
        case "function":
            let parameterized = try codecBoolean(&reader, "isParameterized")
            shape = .function(parameterized: parameterized)
        default:
            throw .invalidTestKind(kind)
        }
        try codecFinish(reader)
        return SwiftTestingTestRecord(id: id, name: name, kind: shape)
    }

    private static func decodeEventRecord(
        _ value: JSONValue
    ) throws(SwiftTestingStreamError) -> SwiftTestingEventRecord {
        let fields = try objectFields(value)
        var reader = try codecObject(value)
        let kindRaw = try codecString(&reader, "kind")
        guard let kind = SwiftTestingEventKind(rawValue: kindRaw) else {
            throw .invalidEventKind(kindRaw)
        }
        let instant = try codecValue(&reader, "instant")
        let seconds = try decodeInstant(instant)
        let messages = try codecArray(&reader, "messages")
        for message in messages {
            try validateMessage(message)
        }
        let testID: SwiftTestingTestID?
        if fields["testID"] != nil {
            testID = try SwiftTestingTestID.parse(codecString(&reader, "testID"))
        } else {
            testID = nil
        }
        let iteration: Int?
        if fields["iteration"] != nil {
            let value = try codecInteger(&reader, "iteration")
            if value < 1 {
                throw .invalidNumber("iteration")
            }
            iteration = value
        } else {
            iteration = nil
        }
        let issue: SwiftTestingIssue?
        if fields["issue"] != nil {
            if kind != .issueRecorded {
                throw .invalidEventPayload("issue outside issueRecorded")
            }
            issue = try decodeIssue(try codecValue(&reader, "issue"))
        } else {
            issue = nil
        }
        if fields["attachment"] != nil {
            if kind != .valueAttached {
                throw .invalidEventPayload("attachment outside valueAttached")
            }
            let attachment = try codecValue(&reader, "attachment")
            try validateAttachment(attachment)
        }
        if kind == .issueRecorded && issue == nil {
            throw .invalidEventPayload("missing issue")
        }
        if kind == .valueAttached && fields["attachment"] == nil {
            throw .invalidEventPayload("missing attachment")
        }
        try codecFinish(reader)
        return SwiftTestingEventRecord(
            kind: kind,
            testID: testID,
            issue: issue,
            secondsSince1970: seconds,
            iteration: iteration
        )
    }

    private static func decodeIssue(_ value: JSONValue) throws(SwiftTestingStreamError) -> SwiftTestingIssue {
        let fields = try objectFields(value)
        var reader = try codecObject(value)
        let isKnown = try codecBoolean(&reader, "isKnown")
        let severity = try codecString(&reader, "severity")
        let isFailure = try codecBoolean(&reader, "isFailure")
        if fields["sourceLocation"] != nil {
            try validateLocation(try codecValue(&reader, "sourceLocation"))
        }
        try codecFinish(reader)
        return SwiftTestingIssue(isKnown: isKnown, isFailure: isFailure, severity: severity)
    }

    private static func decodeInstant(_ value: JSONValue) throws(SwiftTestingStreamError) -> Double {
        var reader = try codecObject(value)
        let absolute = try codecValue(&reader, "absolute")
        let seconds = try codecValue(&reader, "since1970")
        try validateNumber(absolute, field: "absolute")
        let result = try finiteNumber(seconds, field: "since1970")
        try codecFinish(reader)
        return result
    }

    private static func validateLocation(_ value: JSONValue) throws(SwiftTestingStreamError) {
        let fields = try objectFields(value)
        var reader = try codecObject(value)
        if fields["fileID"] != nil {
            let fileID = try codecString(&reader, "fileID")
            if fileID.isEmpty {
                throw .invalidIdentifier("fileID")
            }
        }
        let path = try codecString(&reader, "filePath")
        if path.isEmpty {
            throw .invalidIdentifier("filePath")
        }
        let line = try codecInteger(&reader, "line")
        let column = try codecInteger(&reader, "column")
        if line < 1 || column < 1 {
            throw .invalidNumber("sourceLocation")
        }
        try codecFinish(reader)
    }

    private static func validateMessage(_ value: JSONValue) throws(SwiftTestingStreamError) {
        var reader = try codecObject(value)
        let symbol = try codecString(&reader, "symbol")
        let allowed = ["default", "skip", "pass", "passWithKnownIssue", "fail", "difference", "warning", "details"]
        if !allowed.contains(symbol) {
            throw .invalidMessageSymbol(symbol)
        }
        let text = try codecString(&reader, "text")
        if text.isEmpty {
            throw .invalidIdentifier("message text")
        }
        try codecFinish(reader)
    }

    private static func validateAttachment(_ value: JSONValue) throws(SwiftTestingStreamError) {
        var reader = try codecObject(value)
        let path = try codecString(&reader, "path")
        if !path.hasPrefix("/") {
            throw .invalidIdentifier("attachment path")
        }
        try codecFinish(reader)
    }

    private static func validateBug(_ value: JSONValue) throws(SwiftTestingStreamError) {
        let fields = try objectFields(value)
        var reader = try codecObject(value)
        for key in ["url", "id", "title"] where fields[key] != nil {
            let value = try codecString(&reader, key)
            if value.isEmpty {
                throw .invalidIdentifier("bug " + key)
            }
        }
        try codecFinish(reader)
    }

    private static func validateNumber(
        _ value: JSONValue,
        field: String
    ) throws(SwiftTestingStreamError) {
        let number = try finiteNumber(value, field: field)
        if number < 0 && field == "timeLimit" {
            throw .invalidNumber(field)
        }
    }

    private static func finiteNumber(
        _ value: JSONValue,
        field: String
    ) throws(SwiftTestingStreamError) -> Double {
        guard case .number(let text) = value,
            let number = Double(text), number.isFinite else {
            throw .invalidNumber(field)
        }
        return number
    }

    private static func objectFields(
        _ value: JSONValue
    ) throws(SwiftTestingStreamError) -> [String: JSONValue] {
        guard case .object(let fields) = value else {
            throw .codec(.expectedObject)
        }
        return fields
    }

    private static func codecObject(_ value: JSONValue) throws(SwiftTestingStreamError) -> JSONObjectReader {
        do {
            return try JSONObjectReader(value)
        } catch let error {
            throw .codec(error)
        }
    }

    private static func codecString(
        _ reader: inout JSONObjectReader,
        _ field: String
    ) throws(SwiftTestingStreamError) -> String {
        do {
            return try reader.requiredString(field)
        } catch let error {
            throw .codec(error)
        }
    }

    private static func codecBoolean(
        _ reader: inout JSONObjectReader,
        _ field: String
    ) throws(SwiftTestingStreamError) -> Bool {
        do {
            return try reader.requiredBoolean(field)
        } catch let error {
            throw .codec(error)
        }
    }

    private static func codecInteger(
        _ reader: inout JSONObjectReader,
        _ field: String
    ) throws(SwiftTestingStreamError) -> Int {
        do {
            return try reader.requiredInteger(field)
        } catch let error {
            throw .codec(error)
        }
    }

    private static func codecArray(
        _ reader: inout JSONObjectReader,
        _ field: String
    ) throws(SwiftTestingStreamError) -> [JSONValue] {
        do {
            return try reader.requiredArray(field)
        } catch let error {
            throw .codec(error)
        }
    }

    private static func codecValue(
        _ reader: inout JSONObjectReader,
        _ field: String
    ) throws(SwiftTestingStreamError) -> JSONValue {
        do {
            return try reader.requiredValue(field)
        } catch let error {
            throw .codec(error)
        }
    }

    private static func codecFinish(_ reader: JSONObjectReader) throws(SwiftTestingStreamError) {
        do {
            try reader.finish()
        } catch let error {
            throw .codec(error)
        }
    }
}
