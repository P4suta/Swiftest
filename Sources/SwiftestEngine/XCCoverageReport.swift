import Foundation
import SwiftestCodec
import SwiftestModel
import SwiftestPlatform

public enum XCCoverageError: Error, Equatable, Sendable {
    case codec(StrictJSONError)
    case count(NumericValueError)
    case negativeCount(String)
    case inconsistentCount(String)
    case invalidFraction(String)
    case noTargets
    case noExecutableLines
    case overflow
    case targetCountMismatch(Int)
    case targetNameMismatch(String)
    case productPathMismatch(String)
    case emptyExpectedSources
    case duplicateSource(String)
    case unexpectedSource(String)
    case missingSource(String)
    case sourceOutsideRepository(String)
    case unsafePath(String)
}

public struct XCCoverageReport: Equatable, Sendable {
    public let coveredLines: EvidenceCount
    public let executableLines: EvidenceCount
    public let targetCount: EvidenceCount
    private let targets: [TargetEvidence]

    private struct TargetEvidence: Equatable, Sendable {
        let name: String
        let buildProductPath: String
        let sourcePaths: [String]
    }

    private init(
        coveredLines: EvidenceCount,
        executableLines: EvidenceCount,
        targetCount: EvidenceCount,
        targets: [TargetEvidence]
    ) {
        self.coveredLines = coveredLines
        self.executableLines = executableLines
        self.targetCount = targetCount
        self.targets = targets
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
        var evidence: [TargetEvidence] = []
        for target in targets {
            let validated = try validateTarget(target)
            targetCovered = try add(targetCovered, validated.counts.covered)
            targetExecutable = try add(targetExecutable, validated.counts.executable)
            evidence.append(validated.evidence)
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
            targetCount: targetCount,
            targets: evidence
        )
    }

    func verifyEvidence(
        expectedTargetName: String,
        expectedProductPath: String,
        expectedSourcePaths: Set<String>,
        repositoryRoot: String
    ) throws(XCCoverageError) {
        guard targets.count == 1, targetCount.rawValue == 1,
            let target = targets.first else {
            throw .targetCountMismatch(targets.count)
        }
        guard target.name == expectedTargetName else {
            throw .targetNameMismatch(target.name)
        }
        let product = try Self.regularCanonicalPath(target.buildProductPath)
        let expectedProduct = try Self.regularCanonicalPath(expectedProductPath)
        guard product == expectedProduct else {
            throw .productPathMismatch(target.buildProductPath)
        }
        guard !expectedSourcePaths.isEmpty else {
            throw .emptyExpectedSources
        }
        let root = try Self.canonicalRepositoryRoot(repositoryRoot)
        var expected: Set<String> = []
        for source in expectedSourcePaths.sorted() {
            let canonical = try Self.repositorySource(source, root: root)
            guard expected.insert(canonical).inserted else {
                throw .duplicateSource(source)
            }
        }
        var reported: Set<String> = []
        for source in target.sourcePaths {
            let canonical = try Self.repositorySource(source, root: root)
            guard reported.insert(canonical).inserted else {
                throw .duplicateSource(source)
            }
            guard expected.contains(canonical) else {
                throw .unexpectedSource(source)
            }
        }
        for source in expected.sorted() where !reported.contains(source) {
            throw .missingSource(source)
        }
    }

    private struct Counts {
        let covered: Int
        let executable: Int
    }

    private static func validateTarget(
        _ input: JSONValue
    ) throws(XCCoverageError) -> (counts: Counts, evidence: TargetEvidence) {
        var reader = try object(input)
        let covered = try count(&reader, "coveredLines")
        let executable = try count(&reader, "executableLines")
        try fraction(&reader, "lineCoverage", covered: covered, executable: executable)
        let name = try requiredString(&reader, "name")
        let buildProductPath = try requiredString(&reader, "buildProductPath")
        let files = try array(&reader, "files")
        try finish(reader)
        if covered.rawValue > executable.rawValue {
            throw .inconsistentCount("target.coveredLines")
        }
        var fileCovered = 0
        var fileExecutable = 0
        var sourcePaths: [String] = []
        for file in files {
            let validated = try validateFile(file)
            fileCovered = try add(fileCovered, validated.counts.covered)
            fileExecutable = try add(fileExecutable, validated.counts.executable)
            sourcePaths.append(validated.path)
        }
        if fileCovered != covered.rawValue || fileExecutable != executable.rawValue {
            throw .inconsistentCount("files")
        }
        return (
            Counts(covered: covered.rawValue, executable: executable.rawValue),
            TargetEvidence(name: name, buildProductPath: buildProductPath, sourcePaths: sourcePaths)
        )
    }

    private static func validateFile(
        _ input: JSONValue
    ) throws(XCCoverageError) -> (counts: Counts, path: String) {
        var reader = try object(input)
        let covered = try count(&reader, "coveredLines")
        let executable = try count(&reader, "executableLines")
        try fraction(&reader, "lineCoverage", covered: covered, executable: executable)
        try expectString(&reader, "name")
        let path = try requiredString(&reader, "path")
        let functions = try array(&reader, "functions")
        try finish(reader)
        if covered.rawValue > executable.rawValue {
            throw .inconsistentCount("file.coveredLines")
        }
        for function in functions {
            try validateFunction(function)
        }
        return (Counts(covered: covered.rawValue, executable: executable.rawValue), path)
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
        let value = try requiredString(&reader, key)
        guard !value.isEmpty else {
            throw .codec(.expectedString(key))
        }
    }

    private static func requiredString(
        _ reader: inout JSONObjectReader,
        _ key: String
    ) throws(XCCoverageError) -> String {
        let value: JSONValue
        do {
            value = try reader.requiredValue(key)
        } catch let error {
            throw .codec(error)
        }
        guard case .string(let text) = value else {
            throw .codec(.expectedString(key))
        }
        return text
    }

    private static func canonicalRepositoryRoot(_ path: String) throws(XCCoverageError) -> String {
        let canonical: String
        do {
            canonical = try CanonicalPathBoundary.directory(path)
            guard try FileSystemBoundary.entryKind(path: path) == .directory else {
                throw XCCoverageError.unsafePath(path)
            }
        } catch let error as XCCoverageError {
            throw error
        } catch {
            throw .unsafePath(path)
        }
        return canonical
    }

    private static func repositorySource(
        _ path: String,
        root: String
    ) throws(XCCoverageError) -> String {
        let canonical = try regularCanonicalPath(path)
        guard canonical.hasPrefix(root + "/") else {
            throw .sourceOutsideRepository(path)
        }
        return canonical
    }

    private static func regularCanonicalPath(_ path: String) throws(XCCoverageError) -> String {
        guard path.hasPrefix("/"), !path.hasSuffix("/"), !path.contains("//"),
            !path.utf8.contains(0), !path.contains("$"),
            !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
            throw .unsafePath(path)
        }
        let aliased = path == "/tmp" ? "/private/tmp" :
            path.hasPrefix("/tmp/") ? "/private" + path : path
        let canonical: String
        do {
            guard try FileSystemBoundary.entryKind(path: path) == .file else {
                throw XCCoverageError.unsafePath(path)
            }
            canonical = try CanonicalPathBoundary.existing(aliased)
        } catch let error as XCCoverageError {
            throw error
        } catch {
            throw .unsafePath(path)
        }
        guard canonical == aliased else {
            throw .unsafePath(path)
        }
        return canonical
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
