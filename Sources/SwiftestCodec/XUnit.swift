import Foundation
import SwiftestModel

public enum XUnitCaseStatus: String, CaseIterable, Equatable, Sendable {
    case passed
    case failed
    case errored
    case skipped
}

public struct XUnitTestCase: Equatable, Sendable {
    public let suite: String
    public let name: String
    public let className: String?
    public let status: XUnitCaseStatus

    public init(suite: String, name: String, className: String?, status: XUnitCaseStatus) {
        self.suite = suite
        self.name = name
        self.className = className
        self.status = status
    }
}

public struct XUnitReport: Equatable, Sendable {
    public let tests: EvidenceCount
    public let failures: EvidenceCount
    public let errors: EvidenceCount
    public let skipped: EvidenceCount
    public let cases: [XUnitTestCase]

    public init(
        tests: EvidenceCount,
        failures: EvidenceCount,
        errors: EvidenceCount,
        skipped: EvidenceCount,
        cases: [XUnitTestCase]
    ) {
        self.tests = tests
        self.failures = failures
        self.errors = errors
        self.skipped = skipped
        self.cases = cases
    }
}

public enum XUnitCodecError: Error, Equatable, Sendable {
    case invalidUTF8
    case resourceLimit
    case malformedXML(Int)
    case invalidEntity(String)
    case unsupportedDeclaration
    case duplicateAttribute(String)
    case unknownAttribute(String, String)
    case missingAttribute(String, String)
    case unknownElement(String)
    case invalidCount(String, String)
    case countMismatch(String)
    case duplicateTestCase(String)
    case conflictingCaseStatus(String)
    case unexpectedText(String)
}

public enum XUnitCodec {
    public static func decode(_ data: Data) throws(XUnitCodecError) -> XUnitReport {
        guard String(data: data, encoding: .utf8) != nil else {
            throw .invalidUTF8
        }
        if data.count > 32_000_000 {
            throw .resourceLimit
        }
        var reader = XMLReader(bytes: Array(data))
        let root = try reader.document()
        var cases: [XUnitTestCase] = []
        var identities = Set<String>()
        let counts: XUnitCounts
        switch root.name {
        case "testsuites":
            try validateAttributes(root, allowed: ["name", "tests", "failures", "errors", "skipped", "time"])
            try requireWhitespace(root)
            var aggregate = XUnitCounts.zero
            for child in root.children {
                guard child.name == "testsuite" else {
                    throw .unknownElement(child.name)
                }
                let childCounts = try readSuite(child, cases: &cases, identities: &identities)
                aggregate = try aggregate.adding(childCounts)
            }
            if root.children.isEmpty {
                throw .countMismatch("testsuites-empty")
            }
            try validateOptionalCounts(root, against: aggregate)
            counts = aggregate
        case "testsuite":
            counts = try readSuite(root, cases: &cases, identities: &identities)
        default:
            throw .unknownElement(root.name)
        }
        let tests = try count(counts.tests, field: "tests")
        let failures = try count(counts.failures, field: "failures")
        let errors = try count(counts.errors, field: "errors")
        let skipped = try count(counts.skipped, field: "skipped")
        return XUnitReport(
            tests: tests,
            failures: failures,
            errors: errors,
            skipped: skipped,
            cases: cases
        )
    }

    public static func decodeDocuments(_ documents: [Data]) throws(XUnitCodecError) -> XUnitReport {
        if documents.isEmpty {
            throw .countMismatch("missing-documents")
        }
        var aggregate = XUnitCounts.zero
        var cases: [XUnitTestCase] = []
        var identities = Set<String>()
        for document in documents {
            let report = try decode(document)
            aggregate = try aggregate.adding(XUnitCounts(
                tests: report.tests.rawValue,
                failures: report.failures.rawValue,
                errors: report.errors.rawValue,
                skipped: report.skipped.rawValue
            ))
            for testCase in report.cases {
                let identity = testCase.suite + "\u{0}" + String(describing: testCase.className) + "\u{0}" + testCase.name
                if !identities.insert(identity).inserted {
                    throw .duplicateTestCase(testCase.suite + "." + testCase.name)
                }
                cases.append(testCase)
            }
        }
        return XUnitReport(
            tests: try count(aggregate.tests, field: "tests"),
            failures: try count(aggregate.failures, field: "failures"),
            errors: try count(aggregate.errors, field: "errors"),
            skipped: try count(aggregate.skipped, field: "skipped"),
            cases: cases
        )
    }

    private static func readSuite(
        _ suite: XMLNode,
        cases: inout [XUnitTestCase],
        identities: inout Set<String>
    ) throws(XUnitCodecError) -> XUnitCounts {
        try validateAttributes(
            suite,
            allowed: ["name", "tests", "failures", "errors", "skipped", "time", "timestamp", "id", "package", "hostname"]
        )
        try requireWhitespace(suite)
        let name = try required(suite, "name")
        if name.isEmpty {
            throw .missingAttribute("testsuite", "name")
        }
        var observed = XUnitCounts.zero
        for child in suite.children {
            switch child.name {
            case "testcase":
                let testCase = try readCase(child, suite: name)
                let identity = name + "\u{0}" + String(describing: testCase.className) + "\u{0}" + testCase.name
                if !identities.insert(identity).inserted {
                    throw .duplicateTestCase(name + "." + testCase.name)
                }
                cases.append(testCase)
                observed = try observed.adding(.single(testCase.status))
            case "testsuite":
                let childCounts = try readSuite(child, cases: &cases, identities: &identities)
                observed = try observed.adding(childCounts)
            case "properties":
                try validateProperties(child)
            case "system-out", "system-err":
                try validateAttributes(child, allowed: [])
                if !child.children.isEmpty {
                    throw .unknownElement(child.children[0].name)
                }
            default:
                throw .unknownElement(child.name)
            }
        }
        try validateRequiredCounts(suite, against: observed)
        return observed
    }

    private static func readCase(_ node: XMLNode, suite: String) throws(XUnitCodecError) -> XUnitTestCase {
        try validateAttributes(node, allowed: ["name", "classname", "time", "status", "assertions"])
        try requireWhitespace(node)
        let name = try required(node, "name")
        if name.isEmpty {
            throw .missingAttribute("testcase", "name")
        }
        var status = XUnitCaseStatus.passed
        for child in node.children {
            let next: XUnitCaseStatus
            switch child.name {
            case "failure":
                next = .failed
            case "error":
                next = .errored
            case "skipped":
                next = .skipped
            case "system-out", "system-err":
                try validateAttributes(child, allowed: [])
                if !child.children.isEmpty {
                    throw .unknownElement(child.children[0].name)
                }
                continue
            default:
                throw .unknownElement(child.name)
            }
            try validateAttributes(child, allowed: ["message", "type", "file", "line"])
            if !child.children.isEmpty {
                throw .unknownElement(child.children[0].name)
            }
            if status != .passed {
                throw .conflictingCaseStatus(name)
            }
            status = next
        }
        if let declared = node.attributes["status"] {
            if declared != status.rawValue {
                throw .conflictingCaseStatus(name)
            }
        }
        return XUnitTestCase(
            suite: suite,
            name: name,
            className: node.attributes["classname"],
            status: status
        )
    }

    private static func validateProperties(_ node: XMLNode) throws(XUnitCodecError) {
        try validateAttributes(node, allowed: [])
        try requireWhitespace(node)
        for child in node.children {
            guard child.name == "property" else {
                throw .unknownElement(child.name)
            }
            try validateAttributes(child, allowed: ["name", "value"])
            let name = try required(child, "name")
            let value = try required(child, "value")
            if name.isEmpty || value.isEmpty || !child.children.isEmpty {
                throw .malformedXML(0)
            }
            try requireWhitespace(child)
        }
    }

    private static func validateRequiredCounts(_ node: XMLNode, against observed: XUnitCounts) throws(XUnitCodecError) {
        let tests = try requiredCount(node, "tests")
        let failures = try requiredCount(node, "failures")
        let errors = try requiredCount(node, "errors")
        if tests != observed.tests || failures != observed.failures || errors != observed.errors {
            throw .countMismatch(node.name)
        }
        if let skippedRaw = node.attributes["skipped"] {
            if try parsedCount(skippedRaw, field: "skipped") != observed.skipped {
                throw .countMismatch(node.name + ".skipped")
            }
        }
    }

    private static func validateOptionalCounts(_ node: XMLNode, against observed: XUnitCounts) throws(XUnitCodecError) {
        let named: [(String, Int)] = [
            ("tests", observed.tests),
            ("failures", observed.failures),
            ("errors", observed.errors),
            ("skipped", observed.skipped),
        ]
        for (name, expected) in named {
            if let raw = node.attributes[name] {
                let value = try parsedCount(raw, field: name)
                if value != expected {
                    throw .countMismatch(node.name + "." + name)
                }
            }
        }
    }

    private static func requiredCount(_ node: XMLNode, _ name: String) throws(XUnitCodecError) -> Int {
        try parsedCount(required(node, name), field: name)
    }

    private static func parsedCount(_ raw: String, field: String) throws(XUnitCodecError) -> Int {
        guard !raw.isEmpty,
            raw.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
            let value = Int(raw),
            String(value) == raw else {
            throw .invalidCount(field, raw)
        }
        return value
    }

    private static func count(_ value: Int, field: String) throws(XUnitCodecError) -> EvidenceCount {
        do {
            return try .nonnegative(value)
        } catch {
            throw .invalidCount(field, String(value))
        }
    }

    private static func required(_ node: XMLNode, _ name: String) throws(XUnitCodecError) -> String {
        guard let value = node.attributes[name] else {
            throw .missingAttribute(node.name, name)
        }
        return value
    }

    private static func validateAttributes(_ node: XMLNode, allowed: Set<String>) throws(XUnitCodecError) {
        for attribute in node.attributes.keys where !allowed.contains(attribute) {
            throw .unknownAttribute(node.name, attribute)
        }
    }

    private static func requireWhitespace(_ node: XMLNode) throws(XUnitCodecError) {
        if !node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw .unexpectedText(node.name)
        }
    }
}

private struct XUnitCounts: Equatable {
    let tests: Int
    let failures: Int
    let errors: Int
    let skipped: Int

    static let zero = XUnitCounts(tests: 0, failures: 0, errors: 0, skipped: 0)

    static func single(_ status: XUnitCaseStatus) -> XUnitCounts {
        switch status {
        case .passed:
            XUnitCounts(tests: 1, failures: 0, errors: 0, skipped: 0)
        case .failed:
            XUnitCounts(tests: 1, failures: 1, errors: 0, skipped: 0)
        case .errored:
            XUnitCounts(tests: 1, failures: 0, errors: 1, skipped: 0)
        case .skipped:
            XUnitCounts(tests: 1, failures: 0, errors: 0, skipped: 1)
        }
    }

    func adding(_ other: XUnitCounts) throws(XUnitCodecError) -> XUnitCounts {
        let tests = self.tests.addingReportingOverflow(other.tests)
        let failures = self.failures.addingReportingOverflow(other.failures)
        let errors = self.errors.addingReportingOverflow(other.errors)
        let skipped = self.skipped.addingReportingOverflow(other.skipped)
        if tests.overflow || failures.overflow || errors.overflow || skipped.overflow {
            throw .resourceLimit
        }
        return XUnitCounts(
            tests: tests.partialValue,
            failures: failures.partialValue,
            errors: errors.partialValue,
            skipped: skipped.partialValue
        )
    }
}

private struct XMLNode {
    let name: String
    let attributes: [String: String]
    let children: [XMLNode]
    let text: String
}

private struct XMLReader {
    let bytes: [UInt8]
    var offset = 0
    var nodes = 0

    mutating func document() throws(XUnitCodecError) -> XMLNode {
        if bytes.starts(with: [0xef, 0xbb, 0xbf]) {
            offset = 3
        }
        discardWhitespace()
        if starts(with: "<?xml") {
            try declaration()
            discardWhitespace()
        }
        let root = try element(depth: 0)
        discardWhitespace()
        if offset != bytes.count {
            throw .malformedXML(offset)
        }
        return root
    }

    private mutating func declaration() throws(XUnitCodecError) {
        try consume("<?xml")
        var attributes: [String: String] = [:]
        while !starts(with: "?>") {
            if offset >= bytes.count {
                throw .malformedXML(offset)
            }
            guard skipWhitespace() else {
                throw .unsupportedDeclaration
            }
            if starts(with: "?>") {
                break
            }
            let name = try parseName()
            discardWhitespace()
            try consume("=")
            discardWhitespace()
            let value = try quotedValue()
            if attributes.updateValue(value, forKey: name) != nil {
                throw .duplicateAttribute(name)
            }
        }
        try consume("?>")
        if attributes["version"] != "1.0" {
            throw .unsupportedDeclaration
        }
        for (name, value) in attributes {
            switch name {
            case "version":
                break
            case "encoding":
                if value != "UTF-8" && value != "utf-8" {
                    throw .unsupportedDeclaration
                }
            case "standalone":
                if value != "yes" && value != "no" {
                    throw .unsupportedDeclaration
                }
            default:
                throw .unsupportedDeclaration
            }
        }
    }

    private mutating func element(depth: Int) throws(XUnitCodecError) -> XMLNode {
        if depth > 64 || nodes >= 200_000 {
            throw .resourceLimit
        }
        nodes += 1
        try consume("<")
        let name = try parseName()
        var attributes: [String: String] = [:]
        while true {
            let spaced = skipWhitespace()
            if starts(with: "/>") {
                try consume("/>")
                return XMLNode(name: name, attributes: attributes, children: [], text: "")
            }
            if starts(with: ">") {
                try consume(">")
                break
            }
            if !spaced {
                throw .malformedXML(offset)
            }
            let attribute = try parseName()
            discardWhitespace()
            try consume("=")
            discardWhitespace()
            let value = try quotedValue()
            if attributes.updateValue(value, forKey: attribute) != nil {
                throw .duplicateAttribute(attribute)
            }
        }
        var children: [XMLNode] = []
        var text = ""
        while true {
            if offset >= bytes.count {
                throw .malformedXML(offset)
            }
            if starts(with: "</") {
                try consume("</")
                let closeName = try parseName()
                discardWhitespace()
                try consume(">")
                if closeName != name {
                    throw .malformedXML(offset)
                }
                return XMLNode(name: name, attributes: attributes, children: children, text: text)
            }
            if starts(with: "<") {
                children.append(try element(depth: depth + 1))
            } else {
                text += try textUntilTag()
            }
        }
    }

    private mutating func parseName() throws(XUnitCodecError) -> String {
        let start = offset
        guard offset < bytes.count, isNameStart(bytes[offset]) else {
            throw .malformedXML(offset)
        }
        offset += 1
        while offset < bytes.count && isNameContinuation(bytes[offset]) {
            offset += 1
        }
        return String(decoding: bytes[start..<offset], as: UTF8.self)
    }

    private mutating func quotedValue() throws(XUnitCodecError) -> String {
        guard offset < bytes.count, bytes[offset] == 34 || bytes[offset] == 39 else {
            throw .malformedXML(offset)
        }
        let quote = bytes[offset]
        offset += 1
        let start = offset
        while offset < bytes.count && bytes[offset] != quote {
            if bytes[offset] == 60 {
                throw .malformedXML(offset)
            }
            offset += 1
        }
        if offset >= bytes.count {
            throw .malformedXML(offset)
        }
        let value = try decodedEntities(Array(bytes[start..<offset]))
        offset += 1
        return value
    }

    private mutating func textUntilTag() throws(XUnitCodecError) -> String {
        let start = offset
        while offset < bytes.count && bytes[offset] != 60 {
            offset += 1
        }
        return try decodedEntities(Array(bytes[start..<offset]))
    }

    private func decodedEntities(_ fragment: [UInt8]) throws(XUnitCodecError) -> String {
        var result = ""
        var segmentStart = 0
        var index = 0
        while index < fragment.count {
            if fragment[index] == 38 {
                result += String(decoding: fragment[segmentStart..<index], as: UTF8.self)
                let start = index + 1
                var end = start
                while end < fragment.count && fragment[end] != 59 {
                    end += 1
                }
                if end == fragment.count {
                    throw .malformedXML(offset)
                }
                let entity = String(decoding: fragment[start..<end], as: UTF8.self)
                switch entity {
                case "amp": result += "&"
                case "lt": result += "<"
                case "gt": result += ">"
                case "quot": result += "\""
                case "apos": result += "'"
                default:
                    guard let scalar = numericEntity(entity) else {
                        throw .invalidEntity(entity)
                    }
                    result.unicodeScalars.append(scalar)
                }
                index = end + 1
                segmentStart = index
            } else {
                if fragment[index] < 32 && fragment[index] != 9 && fragment[index] != 10 && fragment[index] != 13 {
                    throw .malformedXML(offset)
                }
                index += 1
            }
        }
        result += String(decoding: fragment[segmentStart..<fragment.count], as: UTF8.self)
        return result
    }

    private func numericEntity(_ text: String) -> Unicode.Scalar? {
        let radix: Int
        let digits: Substring
        if text.hasPrefix("#x") || text.hasPrefix("#X") {
            radix = 16
            digits = text.dropFirst(2)
        } else if text.hasPrefix("#") {
            radix = 10
            digits = text.dropFirst()
        } else {
            return nil
        }
        guard !digits.isEmpty, let number = UInt32(digits, radix: radix),
            number >= 32 || number == 9 || number == 10 || number == 13 else {
            return nil
        }
        return Unicode.Scalar(number)
    }

    private mutating func skipWhitespace() -> Bool {
        let start = offset
        discardWhitespace()
        return offset != start
    }

    private mutating func discardWhitespace() {
        while offset < bytes.count && isWhitespace(bytes[offset]) {
            offset += 1
        }
    }

    private func starts(with text: String) -> Bool {
        let expected = Array(text.utf8)
        if offset + expected.count > bytes.count {
            return false
        }
        return Array(bytes[offset..<(offset + expected.count)]) == expected
    }

    private mutating func consume(_ text: String) throws(XUnitCodecError) {
        guard starts(with: text) else {
            throw .malformedXML(offset)
        }
        offset += text.utf8.count
    }

    private func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 9 || byte == 10 || byte == 13 || byte == 32
    }

    private func isNameStart(_ byte: UInt8) -> Bool {
        (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || byte == 95
    }

    private func isNameContinuation(_ byte: UInt8) -> Bool {
        isNameStart(byte) || (byte >= 48 && byte <= 57) || byte == 45 || byte == 46 || byte == 58
    }
}
