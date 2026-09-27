import Foundation

public enum IdentifierError: Error, Equatable, Sendable {
    case empty
    case tooLong
    case invalidCharacter(Int)
}

public enum NumericValueError: Error, Equatable, Sendable {
    case negative
    case zero
    case overflow
}

public enum ArtifactPathError: Error, Equatable, Sendable {
    case empty
    case absolute
    case parentTraversal
    case selfTraversal
    case emptySegment
    case nul
}

public enum DigestError: Error, Equatable, Sendable {
    case invalidLength
    case invalidCharacter(Int)
    case inputTooLarge
}

private func validateIdentifier(_ value: String) throws(IdentifierError) {
    if value.isEmpty {
        throw .empty
    }
    if value.utf8.count > 128 {
        throw .tooLong
    }
    for (index, byte) in value.utf8.enumerated() {
        let allowed =
            (byte >= 48 && byte <= 57)
            || (byte >= 65 && byte <= 90)
            || (byte >= 97 && byte <= 122)
            || byte == 45
            || byte == 46
            || byte == 58
            || byte == 95
        if !allowed {
            throw .invalidCharacter(index)
        }
    }
}

public struct RunID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    private init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func parse(_ value: String) throws(IdentifierError) -> RunID {
        try validateIdentifier(value)
        return RunID(rawValue: value)
    }

    public var description: String { rawValue }
}

public struct ClaimID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    private init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func parse(_ value: String) throws(IdentifierError) -> ClaimID {
        try validateIdentifier(value)
        return ClaimID(rawValue: value)
    }

    public var description: String { rawValue }
}

public struct WorldID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    private init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func parse(_ value: String) throws(IdentifierError) -> WorldID {
        try validateIdentifier(value)
        return WorldID(rawValue: value)
    }

    package static func baseWorld(definition: Digest, ordinal: UInt) -> WorldID {
        WorldID(rawValue: "world-v1-" + definition.rawValue + "-" + String(ordinal))
    }

    public var description: String { rawValue }
}

public struct MutantID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    private init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func parse(_ value: String) throws(IdentifierError) -> MutantID {
        try validateIdentifier(value)
        return MutantID(rawValue: value)
    }

    public var description: String { rawValue }
}

public struct ScheduleID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    private init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func parse(_ value: String) throws(IdentifierError) -> ScheduleID {
        try validateIdentifier(value)
        return ScheduleID(rawValue: value)
    }

    public var description: String { rawValue }
}

public struct SnapshotID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    private init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func parse(_ value: String) throws(IdentifierError) -> SnapshotID {
        try validateIdentifier(value)
        return SnapshotID(rawValue: value)
    }

    public var description: String { rawValue }
}

public struct TestID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    private init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func parse(_ value: String) throws(IdentifierError) -> TestID {
        try validateIdentifier(value)
        return TestID(rawValue: value)
    }

    public var description: String { rawValue }
}

public struct DeviceID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    private init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func parse(_ value: String) throws(IdentifierError) -> DeviceID {
        try validateIdentifier(value)
        return DeviceID(rawValue: value)
    }

    public var description: String { rawValue }
}

public struct ArtifactPath: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    private init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func parse(_ value: String) throws(ArtifactPathError) -> ArtifactPath {
        if value.isEmpty {
            throw .empty
        }
        if value.hasPrefix("/") {
            throw .absolute
        }
        if value.utf8.contains(0) {
            throw .nul
        }
        let segments = value.split(separator: "/", omittingEmptySubsequences: false)
        if segments.contains("..") {
            throw .parentTraversal
        }
        if segments.contains(".") {
            throw .selfTraversal
        }
        if segments.contains("") {
            throw .emptySegment
        }
        return ArtifactPath(rawValue: value)
    }

    public var description: String { rawValue }
}

public struct IterationCount: Hashable, Sendable, Comparable {
    public let rawValue: Int

    private init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func positive(_ value: Int) throws(NumericValueError) -> IterationCount {
        if value < 0 {
            throw .negative
        }
        if value == 0 {
            throw .zero
        }
        return IterationCount(rawValue: value)
    }

    public static func < (lhs: IterationCount, rhs: IterationCount) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct EvidenceCount: Hashable, Sendable, Comparable {
    public let rawValue: Int

    private init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let zero = EvidenceCount(rawValue: 0)

    public static func nonnegative(_ value: Int) throws(NumericValueError) -> EvidenceCount {
        if value < 0 {
            throw .negative
        }
        return EvidenceCount(rawValue: value)
    }

    public static func < (lhs: EvidenceCount, rhs: EvidenceCount) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct DurationNanoseconds: Hashable, Sendable, Comparable {
    public let rawValue: UInt64

    private init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func measured(_ value: UInt64) -> DurationNanoseconds {
        DurationNanoseconds(rawValue: value)
    }

    public static func < (lhs: DurationNanoseconds, rhs: DurationNanoseconds) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct SchemaVersion: Hashable, Sendable, Comparable {
    public let rawValue: Int

    private init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let v1 = SchemaVersion(rawValue: 1)
    public static let v2 = SchemaVersion(rawValue: 2)

    public static func parse(_ value: Int) throws(NumericValueError) -> SchemaVersion {
        if value < 0 {
            throw .negative
        }
        if value == 0 {
            throw .zero
        }
        return SchemaVersion(rawValue: value)
    }

    public static func < (lhs: SchemaVersion, rhs: SchemaVersion) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct Digest: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    private init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func parse(_ value: String) throws(DigestError) -> Digest {
        if value.utf8.count != 64 {
            throw .invalidLength
        }
        for (index, byte) in value.utf8.enumerated() {
            let isDigit = byte >= 48 && byte <= 57
            let isLowerHex = byte >= 97 && byte <= 102
            if !isDigit && !isLowerHex {
                throw .invalidCharacter(index)
            }
        }
        return Digest(rawValue: value)
    }

    public static func sha256(_ data: Data) throws(DigestError) -> Digest {
        var bytes = Array(data)
        let lengthProduct = UInt64(bytes.count).multipliedReportingOverflow(by: 8)
        if lengthProduct.overflow {
            throw .inputTooLarge
        }
        let bitLength = lengthProduct.partialValue
        bytes.append(0x80)
        while bytes.count % 64 != 56 {
            bytes.append(0)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }

        var state: [UInt32] = [
            0x6a09e667,
            0xbb67ae85,
            0x3c6ef372,
            0xa54ff53a,
            0x510e527f,
            0x9b05688c,
            0x1f83d9ab,
            0x5be0cd19,
        ]

        let constants: [UInt32] = [
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
            0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
            0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
            0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
            0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
            0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
            0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
            0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
            0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
        ]

        for offset in stride(from: 0, to: bytes.count, by: 64) {
            var words = Array(repeating: UInt32(0), count: 64)
            for index in 0..<16 {
                let base = offset + index * 4
                words[index] =
                    UInt32(bytes[base]) << 24
                    | UInt32(bytes[base + 1]) << 16
                    | UInt32(bytes[base + 2]) << 8
                    | UInt32(bytes[base + 3])
            }
            for index in 16..<64 {
                let left = words[index - 15]
                let right = words[index - 2]
                let sigma0 = rotateRight(left, by: 7) ^ rotateRight(left, by: 18) ^ (left >> 3)
                let sigma1 = rotateRight(right, by: 17) ^ rotateRight(right, by: 19) ^ (right >> 10)
                words[index] = modularSum([words[index - 16], sigma0, words[index - 7], sigma1])
            }

            var a = state[0]
            var b = state[1]
            var c = state[2]
            var d = state[3]
            var e = state[4]
            var f = state[5]
            var g = state[6]
            var h = state[7]

            for index in 0..<64 {
                let sum1 = rotateRight(e, by: 6) ^ rotateRight(e, by: 11) ^ rotateRight(e, by: 25)
                let choose = (e & f) ^ ((~e) & g)
                let temporary1 = modularSum([h, sum1, choose, constants[index], words[index]])
                let sum0 = rotateRight(a, by: 2) ^ rotateRight(a, by: 13) ^ rotateRight(a, by: 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let temporary2 = modularSum([sum0, majority])
                h = g
                g = f
                f = e
                e = modularSum([d, temporary1])
                d = c
                c = b
                b = a
                a = modularSum([temporary1, temporary2])
            }

            state[0] = modularSum([state[0], a])
            state[1] = modularSum([state[1], b])
            state[2] = modularSum([state[2], c])
            state[3] = modularSum([state[3], d])
            state[4] = modularSum([state[4], e])
            state[5] = modularSum([state[5], f])
            state[6] = modularSum([state[6], g])
            state[7] = modularSum([state[7], h])
        }

        let hex = Array("0123456789abcdef".utf8)
        var output = [UInt8]()
        output.reserveCapacity(64)
        for word in state {
            for shift in stride(from: 28, through: 0, by: -4) {
                let nibble = Int((word >> UInt32(shift)) & 0x0f)
                output.append(hex[nibble])
            }
        }
        guard let text = String(bytes: output, encoding: .utf8) else {
            throw .invalidLength
        }
        return Digest(rawValue: text)
    }

    public var description: String { rawValue }
}

private func rotateRight(_ value: UInt32, by amount: UInt32) -> UInt32 {
    (value >> amount) | (value << (32 - amount))
}

private func modularSum(_ values: [UInt32]) -> UInt32 {
    var total: UInt32 = 0
    for value in values {
        let addition = total.addingReportingOverflow(value)
        total = addition.partialValue
    }
    return total
}
