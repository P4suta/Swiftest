import Foundation
import SwiftestCodec
import SwiftestModel

public enum XCCoverageError: Error, Equatable, Sendable {
    case codec(StrictJSONError)
    case count(NumericValueError)
    case negativeCount(String)
    case inconsistentCount(String)
    case invalidFraction(String)
    case noTargets
    case noExecutableLines
    case overflow
}

public struct XCCoverageReport: Equatable, Sendable {
    public let coveredLines: EvidenceCount
    public let executableLines: EvidenceCount
    public let targetCount: EvidenceCount

    public init(coveredLines: EvidenceCount, executableLines: EvidenceCount, targetCount: EvidenceCount) {
        self.coveredLines = coveredLines
        self.executableLines = executableLines
        self.targetCount = targetCount
    }

    public static func decode(_ data: Data) throws(XCCoverageError) -> XCCoverageReport {
        let document: JSONValue
        do {
            document = try StrictJSON.decode(data)
        } catch let error {
            throw .codec(error)
        }
        var reader = try object(document)
        let covered = try count(&reader, "coveredLines")
        let executable = try count(&reader, "executableLines")
        try fraction(&reader, "lineCoverage", covered: covered, executable: executable)
        let targets = try array(&reader, "targets")
        try finish(reader)
        if targets.isEmpty {
            throw .noTargets
        }
        if executable.rawValue == 0 {
            throw .noExecutableLines
        }
        if covered.rawValue > executable.rawValue {
            throw .inconsistentCount("coveredLines")
        }
        var targetCovered = 0
        var targetExecutable = 0
        for target in targets {
            let counts = try validateTarget(target)
            targetCovered = try add(targetCovered, counts.covered)
            targetExecutable = try add(targetExecutable, counts.executable)
        }
        if targetCovered != covered.rawValue || targetExecutable != executable.rawValue {
            throw .inconsistentCount("targets")
        }
        let targetCount: EvidenceCount
        do {
            targetCount = try .nonnegative(targets.count)
        } catch let error {
            throw .count(error)
        }
        return XCCoverageReport(
            coveredLines: covered,
            executableLines: executable,
            targetCount: targetCount
        )
    }

    private struct Counts {
        let covered: Int
        let executable: Int
    }

    private static func validateTarget(_ input: JSONValue) throws(XCCoverageError) -> Counts {
        var reader = try object(input)
        let covered = try count(&reader, "coveredLines")
        let executable = try count(&reader, "executableLines")
        try fraction(&reader, "lineCoverage", covered: covered, executable: executable)
        try expectString(&reader, "name")
        try expectString(&reader, "buildProductPath")
        let files = try array(&reader, "files")
        try finish(reader)
        if covered.rawValue > executable.rawValue {
            throw .inconsistentCount("target.coveredLines")
        }
        var fileCovered = 0
        var fileExecutable = 0
        for file in files {
            let counts = try validateFile(file)
            fileCovered = try add(fileCovered, counts.covered)
            fileExecutable = try add(fileExecutable, counts.executable)
        }
        if fileCovered != covered.rawValue || fileExecutable != executable.rawValue {
            throw .inconsistentCount("files")
        }
        return Counts(covered: covered.rawValue, executable: executable.rawValue)
    }

    private static func validateFile(_ input: JSONValue) throws(XCCoverageError) -> Counts {
        var reader = try object(input)
        let covered = try count(&reader, "coveredLines")
        let executable = try count(&reader, "executableLines")
        try fraction(&reader, "lineCoverage", covered: covered, executable: executable)
        try expectString(&reader, "name")
        try expectString(&reader, "path")
        let functions = try array(&reader, "functions")
        try finish(reader)
        if covered.rawValue > executable.rawValue {
            throw .inconsistentCount("file.coveredLines")
        }
        for function in functions {
            try validateFunction(function)
        }
        return Counts(covered: covered.rawValue, executable: executable.rawValue)
    }

    private static func validateFunction(_ input: JSONValue) throws(XCCoverageError) {
        var reader = try object(input)
        let covered = try count(&reader, "coveredLines")
        let executable = try count(&reader, "executableLines")
        try fraction(&reader, "lineCoverage", covered: covered, executable: executable)
        try expectNonnegativeInteger(&reader, "lineNumber")
        try expectNonnegativeInteger(&reader, "executionCount")
        try expectString(&reader, "name")
        try finish(reader)
        if covered.rawValue > executable.rawValue {
            throw .inconsistentCount("function")
        }
    }

    private static func add(_ left: Int, _ right: Int) throws(XCCoverageError) -> Int {
        let added = left.addingReportingOverflow(right)
        if added.overflow {
            throw .overflow
        }
        return added.partialValue
    }

    private static func object(_ input: JSONValue) throws(XCCoverageError) -> JSONObjectReader {
        do {
            return try JSONObjectReader(input)
        } catch let error {
            throw .codec(error)
        }
    }

    private static func count(
        _ reader: inout JSONObjectReader,
        _ key: String
    ) throws(XCCoverageError) -> EvidenceCount {
        let raw: Int
        do {
            raw = try reader.requiredInteger(key)
        } catch let error {
            throw .codec(error)
        }
        if raw < 0 {
            throw .negativeCount(key)
        }
        do {
            return try .nonnegative(raw)
        } catch let error {
            throw .count(error)
        }
    }

    private static func fraction(
        _ reader: inout JSONObjectReader,
        _ key: String,
        covered: EvidenceCount,
        executable: EvidenceCount
    ) throws(XCCoverageError) {
        let value: JSONValue
        do {
            value = try reader.requiredValue(key)
        } catch let error {
            throw .codec(error)
        }
        guard case .number(let digits) = value,
            let fraction = Double(digits), fraction.isFinite,
            fraction >= 0, fraction <= 1 else {
            throw .invalidFraction(key)
        }
        if executable.rawValue > 0 {
            let expected = Double(covered.rawValue) / Double(executable.rawValue)
            if abs(fraction - expected) > 0.000000001 {
                throw .invalidFraction(key)
            }
        }
    }

    private static func expectNonnegativeInteger(
        _ reader: inout JSONObjectReader,
        _ key: String
    ) throws(XCCoverageError) {
        let raw: Int
        do {
            raw = try reader.requiredInteger(key)
        } catch let error {
            throw .codec(error)
        }
        if raw < 0 {
            throw .negativeCount(key)
        }
    }

    private static func expectString(
        _ reader: inout JSONObjectReader,
        _ key: String
    ) throws(XCCoverageError) {
        let value: JSONValue
        do {
            value = try reader.requiredValue(key)
        } catch let error {
            throw .codec(error)
        }
        guard case .string = value else {
            throw .codec(.expectedString(key))
        }
    }

    private static func array(
        _ reader: inout JSONObjectReader,
        _ key: String
    ) throws(XCCoverageError) -> [JSONValue] {
        do {
            return try reader.requiredArray(key)
        } catch let error {
            throw .codec(error)
        }
    }

    private static func finish(_ reader: JSONObjectReader) throws(XCCoverageError) {
        do {
            try reader.finish()
        } catch let error {
            throw .codec(error)
        }
    }
}
