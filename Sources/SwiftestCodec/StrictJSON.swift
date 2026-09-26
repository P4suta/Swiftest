import Foundation
import SwiftestModel

public indirect enum JSONValue: Equatable, Sendable {
    case null
    case boolean(Bool)
    case number(String)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

public enum StrictJSONError: Error, Equatable, Sendable {
    case invalidUTF8
    case unexpectedEnd(Int)
    case unexpectedByte(Int, UInt8)
    case trailingInput(Int)
    case duplicateKey(Int, String)
    case invalidEscape(Int)
    case invalidUnicodeEscape(Int)
    case unpairedSurrogate(Int)
    case invalidNumber(Int)
    case expectedObject
    case expectedArray(String)
    case expectedString(String)
    case expectedBoolean(String)
    case expectedInteger(String)
    case missingField(String)
    case unknownField(String)
    case ambiguousUnion([String])
    case unknownUnionTag(String)
}

public enum StrictJSON {
    public static func decode(_ data: Data) throws(StrictJSONError) -> JSONValue {
        guard String(data: data, encoding: .utf8) != nil else {
            throw .invalidUTF8
        }
        var parser = Parser(bytes: Array(data))
        return try parser.parseDocument()
    }

    public static func encode(_ value: JSONValue) -> Data {
        Data(render(value).utf8)
    }

    public static func canonicalDigest(_ value: JSONValue) throws(DigestError) -> Digest {
        try Digest.sha256(encode(value))
    }

    public static func render(_ value: JSONValue) -> String {
        switch value {
        case .null:
            return "null"
        case .boolean(let value):
            return value ? "true" : "false"
        case .number(let value):
            return value
        case .string(let value):
            return renderString(value)
        case .array(let values):
            return "[" + values.map(render).joined(separator: ",") + "]"
        case .object(let fields):
            let entries = fields.sorted { left, right in
                left.key < right.key
            }.map { entry in
                renderString(entry.key) + ":" + render(entry.value)
            }
            return "{" + entries.joined(separator: ",") + "}"
        }
    }
}

public struct JSONObjectReader {
    private let fields: [String: JSONValue]
    private var consumed: Set<String>

    public init(_ value: JSONValue) throws(StrictJSONError) {
        guard case .object(let fields) = value else {
            throw .expectedObject
        }
        self.fields = fields
        self.consumed = []
    }

    public mutating func requiredValue(_ key: String) throws(StrictJSONError) -> JSONValue {
        guard let value = fields[key] else {
            throw .missingField(key)
        }
        consumed.insert(key)
        return value
    }

    public mutating func requiredString(_ key: String) throws(StrictJSONError) -> String {
        let value = try requiredValue(key)
        guard case .string(let string) = value else {
            throw .expectedString(key)
        }
        return string
    }

    public mutating func requiredBoolean(_ key: String) throws(StrictJSONError) -> Bool {
        let value = try requiredValue(key)
        guard case .boolean(let boolean) = value else {
            throw .expectedBoolean(key)
        }
        return boolean
    }

    public mutating func requiredInteger(_ key: String) throws(StrictJSONError) -> Int {
        let value = try requiredValue(key)
        guard case .number(let number) = value, let integer = Int(number) else {
            throw .expectedInteger(key)
        }
        return integer
    }

    public mutating func requiredArray(_ key: String) throws(StrictJSONError) -> [JSONValue] {
        let value = try requiredValue(key)
        guard case .array(let array) = value else {
            throw .expectedArray(key)
        }
        return array
    }

    public mutating func exclusiveUnion(
        allowedTags: Set<String>
    ) throws(StrictJSONError) -> (tag: String, value: JSONValue) {
        let matching = fields.keys.filter { allowedTags.contains($0) }.sorted()
        if matching.count != 1 {
            throw .ambiguousUnion(matching)
        }
        let tag = matching[0]
        guard let value = fields[tag] else {
            throw .missingField(tag)
        }
        consumed.insert(tag)
        return (tag, value)
    }

    public func finish() throws(StrictJSONError) {
        let unknown = Set(fields.keys).subtracting(consumed).sorted()
        if let first = unknown.first {
            throw .unknownField(first)
        }
    }
}

private struct Parser {
    let bytes: [UInt8]
    var index: Int = 0

    mutating func parseDocument() throws(StrictJSONError) -> JSONValue {
        skipWhitespace()
        let value = try parseValue()
        skipWhitespace()
        if index != bytes.count {
            throw .trailingInput(index)
        }
        return value
    }

    mutating func parseValue() throws(StrictJSONError) -> JSONValue {
        guard let byte = current else {
            throw .unexpectedEnd(index)
        }
        switch byte {
        case 110:
            try consumeLiteral([110, 117, 108, 108])
            return .null
        case 116:
            try consumeLiteral([116, 114, 117, 101])
            return .boolean(true)
        case 102:
            try consumeLiteral([102, 97, 108, 115, 101])
            return .boolean(false)
        case 34:
            return .string(try parseString())
        case 91:
            return .array(try parseArray())
        case 123:
            return .object(try parseObject())
        case 45, 48...57:
            return .number(try parseNumber())
        default:
            throw .unexpectedByte(index, byte)
        }
    }

    mutating func parseArray() throws(StrictJSONError) -> [JSONValue] {
        try consume(91)
        skipWhitespace()
        var values: [JSONValue] = []
        if current == 93 {
            index += 1
            return values
        }
        while true {
            skipWhitespace()
            values.append(try parseValue())
            skipWhitespace()
            guard let byte = current else {
                throw .unexpectedEnd(index)
            }
            if byte == 93 {
                index += 1
                return values
            }
            if byte != 44 {
                throw .unexpectedByte(index, byte)
            }
            index += 1
        }
    }

    mutating func parseObject() throws(StrictJSONError) -> [String: JSONValue] {
        try consume(123)
        skipWhitespace()
        var fields: [String: JSONValue] = [:]
        if current == 125 {
            index += 1
            return fields
        }
        while true {
            skipWhitespace()
            guard current == 34 else {
                if let byte = current {
                    throw .unexpectedByte(index, byte)
                }
                throw .unexpectedEnd(index)
            }
            let keyOffset = index
            let key = try parseString()
            if fields[key] != nil {
                throw .duplicateKey(keyOffset, key)
            }
            skipWhitespace()
            try consume(58)
            skipWhitespace()
            fields[key] = try parseValue()
            skipWhitespace()
            guard let byte = current else {
                throw .unexpectedEnd(index)
            }
            if byte == 125 {
                index += 1
                return fields
            }
            if byte != 44 {
                throw .unexpectedByte(index, byte)
            }
            index += 1
        }
    }

    mutating func parseString() throws(StrictJSONError) -> String {
        try consume(34)
        var result = ""
        var segmentStart = index
        while let byte = current {
            if byte == 34 {
                try appendUTF8Segment(from: segmentStart, to: index, into: &result)
                index += 1
                return result
            }
            if byte == 92 {
                try appendUTF8Segment(from: segmentStart, to: index, into: &result)
                index += 1
                try appendEscape(into: &result)
                segmentStart = index
                continue
            }
            if byte < 0x20 {
                throw .unexpectedByte(index, byte)
            }
            index += 1
        }
        throw .unexpectedEnd(index)
    }

    mutating func appendEscape(into result: inout String) throws(StrictJSONError) {
        guard let byte = current else {
            throw .unexpectedEnd(index)
        }
        index += 1
        switch byte {
        case 34:
            result.append("\"")
        case 47:
            result.append("/")
        case 92:
            result.append("\\")
        case 98:
            result.append("\u{08}")
        case 102:
            result.append("\u{0c}")
        case 110:
            result.append("\n")
        case 114:
            result.append("\r")
        case 116:
            result.append("\t")
        case 117:
            let firstOffset = index
            let first = try parseHexQuad()
            if first >= 0xd800 && first <= 0xdbff {
                guard current == 92 else {
                    throw .unpairedSurrogate(firstOffset)
                }
                index += 1
                guard current == 117 else {
                    throw .unpairedSurrogate(firstOffset)
                }
                index += 1
                let second = try parseHexQuad()
                if second < 0xdc00 || second > 0xdfff {
                    throw .unpairedSurrogate(firstOffset)
                }
                let scalarValue = 0x10000 + ((first - 0xd800) << 10) + (second - 0xdc00)
                guard let scalar = Unicode.Scalar(scalarValue) else {
                    throw .invalidUnicodeEscape(firstOffset)
                }
                result.unicodeScalars.append(scalar)
            } else if first >= 0xdc00 && first <= 0xdfff {
                throw .unpairedSurrogate(firstOffset)
            } else {
                guard let scalar = Unicode.Scalar(first) else {
                    throw .invalidUnicodeEscape(firstOffset)
                }
                result.unicodeScalars.append(scalar)
            }
        default:
            throw .invalidEscape(index - 1)
        }
    }

    mutating func parseHexQuad() throws(StrictJSONError) -> UInt32 {
        let start = index
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard let byte = current else {
                throw .unexpectedEnd(index)
            }
            let digit: UInt32
            switch byte {
            case 48...57:
                digit = UInt32(byte - 48)
            case 65...70:
                digit = UInt32(byte - 55)
            case 97...102:
                digit = UInt32(byte - 87)
            default:
                throw .invalidUnicodeEscape(start)
            }
            value = (value << 4) | digit
            index += 1
        }
        return value
    }

    mutating func parseNumber() throws(StrictJSONError) -> String {
        let start = index
        if current == 45 {
            index += 1
        }
        guard let first = current else {
            throw .invalidNumber(start)
        }
        if first == 48 {
            index += 1
            if let next = current, next >= 48 && next <= 57 {
                throw .invalidNumber(start)
            }
        } else if first >= 49 && first <= 57 {
            consumeDigits()
        } else {
            throw .invalidNumber(start)
        }
        if current == 46 {
            index += 1
            guard let next = current, next >= 48 && next <= 57 else {
                throw .invalidNumber(start)
            }
            consumeDigits()
        }
        if current == 101 || current == 69 {
            index += 1
            if current == 43 || current == 45 {
                index += 1
            }
            guard let next = current, next >= 48 && next <= 57 else {
                throw .invalidNumber(start)
            }
            consumeDigits()
        }
        let numberBytes = Array(bytes[start..<index])
        guard let number = String(bytes: numberBytes, encoding: .utf8) else {
            throw .invalidNumber(start)
        }
        return number
    }

    mutating func consumeDigits() {
        while let byte = current, byte >= 48 && byte <= 57 {
            index += 1
        }
    }

    mutating func appendUTF8Segment(
        from start: Int,
        to end: Int,
        into result: inout String
    ) throws(StrictJSONError) {
        let segment = Array(bytes[start..<end])
        guard let text = String(bytes: segment, encoding: .utf8) else {
            throw .invalidUTF8
        }
        result.append(text)
    }

    mutating func consumeLiteral(_ literal: [UInt8]) throws(StrictJSONError) {
        for expected in literal {
            try consume(expected)
        }
    }

    mutating func consume(_ expected: UInt8) throws(StrictJSONError) {
        guard let byte = current else {
            throw .unexpectedEnd(index)
        }
        if byte != expected {
            throw .unexpectedByte(index, byte)
        }
        index += 1
    }

    mutating func skipWhitespace() {
        while let byte = current, byte == 32 || byte == 9 || byte == 10 || byte == 13 {
            index += 1
        }
    }

    var current: UInt8? {
        if index >= bytes.count {
            return nil
        }
        return bytes[index]
    }
}

private func renderString(_ value: String) -> String {
    var output = "\""
    for scalar in value.unicodeScalars {
        switch scalar.value {
        case 0x22:
            output.append("\\\"")
        case 0x5c:
            output.append("\\\\")
        case 0x08:
            output.append("\\b")
        case 0x0c:
            output.append("\\f")
        case 0x0a:
            output.append("\\n")
        case 0x0d:
            output.append("\\r")
        case 0x09:
            output.append("\\t")
        case 0x00...0x1f:
            let digits = String(scalar.value, radix: 16, uppercase: false)
            output.append("\\u")
            output.append(String(repeating: "0", count: 4 - digits.count))
            output.append(digits)
        default:
            output.unicodeScalars.append(scalar)
        }
    }
    output.append("\"")
    return output
}
