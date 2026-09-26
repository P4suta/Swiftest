import Foundation
import SwiftestCodec

enum SourceFlavor: Equatable {
    case hash
    case lean
    case json
    case plain
}

struct LexedComment: Equatable {
    let offset: Int
    let text: String
}

enum OtherSourceLexer {
    static func comments(in source: String, flavor: SourceFlavor) -> [LexedComment] {
        switch flavor {
        case .hash:
            hashComments(in: source)
        case .lean:
            leanComments(in: source)
        case .json, .plain:
            []
        }
    }

    static func validatesJSON(_ data: Data) -> Bool {
        do {
            switch try StrictJSON.decode(data) {
            case .null, .boolean, .number, .string, .array, .object:
                return true
            }
        } catch {
            return false
        }
    }

    private static func hashComments(in source: String) -> [LexedComment] {
        let bytes = Array(source.utf8)
        var comments: [LexedComment] = []
        var index = 0
        var quote: UInt8?
        var escaped = false
        while index < bytes.count {
            let byte = bytes[index]
            if let activeQuote = quote {
                if escaped {
                    escaped = false
                } else if byte == 92 && activeQuote == 34 {
                    escaped = true
                } else if byte == activeQuote {
                    quote = nil
                }
                index += 1
                continue
            }
            if byte == 34 || byte == 39 {
                quote = byte
                index += 1
                continue
            }
            if byte == 35 {
                let end = lineEnd(bytes: bytes, from: index)
                let text = String(decoding: bytes[index..<end], as: UTF8.self)
                comments.append(LexedComment(offset: index, text: text))
                index = end
                continue
            }
            index += 1
        }
        return comments
    }

    private static func leanComments(in source: String) -> [LexedComment] {
        let bytes = Array(source.utf8)
        var comments: [LexedComment] = []
        var index = 0
        var inString = false
        var escaped = false
        while index < bytes.count {
            let byte = bytes[index]
            let next = index + 1 < bytes.count ? bytes[index + 1] : 0
            if inString {
                if escaped {
                    escaped = false
                } else if byte == 92 {
                    escaped = true
                } else if byte == 34 {
                    inString = false
                }
                index += 1
                continue
            }
            if byte == 34 {
                inString = true
                index += 1
                continue
            }
            if byte == 45 && next == 45 {
                let end = lineEnd(bytes: bytes, from: index)
                let text = String(decoding: bytes[index..<end], as: UTF8.self)
                comments.append(LexedComment(offset: index, text: text))
                index = end
                continue
            }
            if byte == 47 && next == 45 {
                let start = index
                index += 2
                var depth = 1
                while index < bytes.count && depth > 0 {
                    let current = bytes[index]
                    let following = index + 1 < bytes.count ? bytes[index + 1] : 0
                    if current == 47 && following == 45 {
                        depth += 1
                        index += 2
                    } else if current == 45 && following == 47 {
                        depth -= 1
                        index += 2
                    } else {
                        index += 1
                    }
                }
                let text = String(decoding: bytes[start..<index], as: UTF8.self)
                comments.append(LexedComment(offset: start, text: text))
                continue
            }
            index += 1
        }
        return comments
    }

    private static func lineEnd(bytes: [UInt8], from start: Int) -> Int {
        var index = start
        while index < bytes.count && bytes[index] != 10 {
            index += 1
        }
        return index
    }
}
