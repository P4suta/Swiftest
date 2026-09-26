import Foundation
import SwiftestModel
import SwiftestPlatform

public enum MutationSchema: String, CaseIterable, Hashable, Sendable {
    case equalityNegation = "equality-negation"
    case boundaryShift = "boundary-shift"
    case booleanFlip = "boolean-flip"
    case conjunctionDisjunction = "conjunction-disjunction"
    case arithmeticReplacement = "arithmetic-replacement"
}

public struct MutationCandidate: Hashable, Sendable {
    public let id: MutantID
    public let schema: MutationSchema
    public let offset: Int
    public let length: Int
    public let replacement: String

    public init(
        id: MutantID,
        schema: MutationSchema,
        offset: Int,
        length: Int,
        replacement: String
    ) {
        self.id = id
        self.schema = schema
        self.offset = offset
        self.length = length
        self.replacement = replacement
    }
}

public enum MutationError: Error, Equatable, Sendable {
    case invalidIdentifier(IdentifierError)
    case invalidOffset(Int)
    case invalidSourceEncoding
    case compiler(PlatformError)
    case malformedSIL(Int)
}

public enum CompilerAcceptance: String, CaseIterable, Sendable {
    case accepted
    case rejected
}

public enum MutationPhaseStatus: String, CaseIterable, Sendable {
    case passed
    case failed
    case notObserved = "not-observed"
}

public struct MutationAssessment: Equatable, Sendable {
    public let mutant: MutantID
    public let compilerAcceptance: CompilerAcceptance
    public let reached: MutationPhaseStatus
    public let infected: MutationPhaseStatus
    public let cleanControl: MutationPhaseStatus
    public let detected: MutationPhaseStatus
    public let reconfirmed: MutationPhaseStatus

    public init(
        mutant: MutantID,
        compilerAcceptance: CompilerAcceptance,
        reached: MutationPhaseStatus,
        infected: MutationPhaseStatus,
        cleanControl: MutationPhaseStatus,
        detected: MutationPhaseStatus,
        reconfirmed: MutationPhaseStatus
    ) {
        self.mutant = mutant
        self.compilerAcceptance = compilerAcceptance
        self.reached = reached
        self.infected = infected
        self.cleanControl = cleanControl
        self.detected = detected
        self.reconfirmed = reconfirmed
    }
}

public enum MutationEngine {
    public static func discover(in source: String) throws(MutationError) -> [MutationCandidate] {
        let bytes = Array(source.utf8)
        let codeMask = lexicalCodeMask(bytes)
        var candidates: [MutationCandidate] = []
        var index = 0
        while index < bytes.count {
            if !codeMask[index] {
                index += 1
                continue
            }
            let remaining = bytes.count - index
            let match = mutation(at: index, bytes: bytes, codeMask: codeMask, remaining: remaining)
            if let match {
                let rawID = "mutant-" + String(index) + "-" + match.schema.rawValue
                let id: MutantID
                do {
                    id = try MutantID.parse(rawID)
                } catch let error {
                    throw .invalidIdentifier(error)
                }
                candidates.append(MutationCandidate(
                    id: id,
                    schema: match.schema,
                    offset: index,
                    length: match.length,
                    replacement: match.replacement
                ))
                index += match.length
            } else {
                index += 1
            }
        }
        return candidates
    }

    public static func apply(
        _ candidate: MutationCandidate,
        to source: String
    ) throws(MutationError) -> String {
        var bytes = Array(source.utf8)
        let end = candidate.offset + candidate.length
        if candidate.offset < 0 || end > bytes.count {
            throw .invalidOffset(candidate.offset)
        }
        bytes.replaceSubrange(candidate.offset..<end, with: candidate.replacement.utf8)
        guard let result = String(bytes: bytes, encoding: .utf8) else {
            throw .invalidSourceEncoding
        }
        return result
    }

    private static func mutation(
        at index: Int,
        bytes: [UInt8],
        codeMask: [Bool],
        remaining: Int
    ) -> (schema: MutationSchema, length: Int, replacement: String)? {
        if remaining >= 2 && codeMask[index + 1] {
            let pair = [bytes[index], bytes[index + 1]]
            switch pair {
            case [61, 61]:
                return (.equalityNegation, 2, "!=")
            case [33, 61]:
                return (.equalityNegation, 2, "==")
            case [60, 61]:
                return (.boundaryShift, 2, "<")
            case [62, 61]:
                return (.boundaryShift, 2, ">")
            case [38, 38]:
                return (.conjunctionDisjunction, 2, "||")
            case [124, 124]:
                return (.conjunctionDisjunction, 2, "&&")
            default:
                break
            }
        }
        if matchesWord("true", at: index, bytes: bytes, codeMask: codeMask) {
            return (.booleanFlip, 4, "false")
        }
        if matchesWord("false", at: index, bytes: bytes, codeMask: codeMask) {
            return (.booleanFlip, 5, "true")
        }
        switch bytes[index] {
        case 60:
            return (.boundaryShift, 1, "<=")
        case 62:
            return (.boundaryShift, 1, ">=")
        case 43:
            return (.arithmeticReplacement, 1, "-")
        case 45:
            return (.arithmeticReplacement, 1, "+")
        default:
            return nil
        }
    }

    private static func matchesWord(
        _ word: String,
        at index: Int,
        bytes: [UInt8],
        codeMask: [Bool]
    ) -> Bool {
        let candidate = Array(word.utf8)
        if index + candidate.count > bytes.count {
            return false
        }
        for offset in candidate.indices {
            if !codeMask[index + offset] || bytes[index + offset] != candidate[offset] {
                return false
            }
        }
        let beforeIsIdentifier = index > 0 && isIdentifierByte(bytes[index - 1])
        let after = index + candidate.count
        let afterIsIdentifier = after < bytes.count && isIdentifierByte(bytes[after])
        return !beforeIsIdentifier && !afterIsIdentifier
    }

    private static func lexicalCodeMask(_ bytes: [UInt8]) -> [Bool] {
        enum State {
            case code
            case string
            case lineComment
            case blockComment(Int)
        }
        var mask = Array(repeating: false, count: bytes.count)
        var state = State.code
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            let next = index + 1 < bytes.count ? bytes[index + 1] : 0
            switch state {
            case .code:
                if byte == 34 {
                    state = .string
                } else if byte == 47 && next == 47 {
                    state = .lineComment
                } else if byte == 47 && next == 42 {
                    state = .blockComment(1)
                } else {
                    mask[index] = true
                }
            case .string:
                if byte == 92 {
                    index += 1
                } else if byte == 34 {
                    state = .code
                }
            case .lineComment:
                if byte == 10 {
                    state = .code
                    mask[index] = true
                }
            case .blockComment(let depth):
                if byte == 47 && next == 42 {
                    state = .blockComment(depth + 1)
                    index += 1
                } else if byte == 42 && next == 47 {
                    let nextDepth = depth - 1
                    state = nextDepth == 0 ? .code : .blockComment(nextDepth)
                    index += 1
                }
            }
            index += 1
        }
        return mask
    }

    private static func isIdentifierByte(_ byte: UInt8) -> Bool {
        (byte >= 48 && byte <= 57)
            || (byte >= 65 && byte <= 90)
            || (byte >= 97 && byte <= 122)
            || byte == 95
    }
}
