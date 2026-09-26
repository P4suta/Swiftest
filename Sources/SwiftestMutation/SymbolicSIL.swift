import Foundation

public indirect enum SymbolicValue: Equatable, Sendable {
    case integer(Int)
    case argument(Int)
    case add(SymbolicValue, SymbolicValue)
    case subtract(SymbolicValue, SymbolicValue)
    case equal(SymbolicValue, SymbolicValue)
    case unknown(String)
}

public enum SymbolicComparison: String, CaseIterable, Sendable {
    case identical
    case different
    case unknown
}

public enum SymbolicSIL {
    public static func compare(
        original: String,
        mutant: String
    ) throws(MutationError) -> SymbolicComparison {
        let left = try returnValue(original)
        let right = try returnValue(mutant)
        if left == right {
            return .identical
        }
        if containsUnknown(left) || containsUnknown(right) {
            return .unknown
        }
        return .different
    }

    private static func returnValue(_ source: String) throws(MutationError) -> SymbolicValue {
        var values: [String: SymbolicValue] = [:]
        let lines = source.split(separator: "\n", omittingEmptySubsequences: true)
        for (lineNumber, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("return ") {
                let name = String(line.dropFirst(7))
                return value(named: name, values: values)
            }
            let pieces = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            if pieces.count < 3 || pieces[1] != "=" {
                continue
            }
            let target = pieces[0]
            switch pieces[2] {
            case "integer_literal":
                guard pieces.count == 4, let value = Int(pieces[3]) else {
                    throw .malformedSIL(lineNumber)
                }
                values[target] = .integer(value)
            case "argument":
                guard pieces.count == 4, let value = Int(pieces[3]) else {
                    throw .malformedSIL(lineNumber)
                }
                values[target] = .argument(value)
            case "add", "subtract", "equal":
                guard pieces.count == 5 else {
                    throw .malformedSIL(lineNumber)
                }
                let left = value(named: pieces[3], values: values)
                let right = value(named: pieces[4], values: values)
                switch pieces[2] {
                case "add":
                    values[target] = normalizeAdd(left, right)
                case "subtract":
                    values[target] = .subtract(left, right)
                case "equal":
                    values[target] = normalizeEqual(left, right)
                default:
                    values[target] = .unknown(pieces[2])
                }
            default:
                values[target] = .unknown(pieces[2])
            }
        }
        throw .malformedSIL(lines.count)
    }

    private static func value(
        named name: String,
        values: [String: SymbolicValue]
    ) -> SymbolicValue {
        if let value = values[name] {
            return value
        }
        return .unknown(name)
    }

    private static func normalizeAdd(_ left: SymbolicValue, _ right: SymbolicValue) -> SymbolicValue {
        if String(describing: left) <= String(describing: right) {
            return .add(left, right)
        }
        return .add(right, left)
    }

    private static func normalizeEqual(_ left: SymbolicValue, _ right: SymbolicValue) -> SymbolicValue {
        if String(describing: left) <= String(describing: right) {
            return .equal(left, right)
        }
        return .equal(right, left)
    }

    private static func containsUnknown(_ value: SymbolicValue) -> Bool {
        switch value {
        case .unknown:
            true
        case .integer, .argument:
            false
        case .add(let left, let right), .subtract(let left, let right), .equal(let left, let right):
            containsUnknown(left) || containsUnknown(right)
        }
    }
}
