import Foundation
import SwiftestModel

public enum RandomError: Error, Equatable, Sendable {
    case zeroUpperBound
    case invalidRange
}

public struct DeterministicRandom: Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        let multiplication = state.multipliedReportingOverflow(by: 6364136223846793005)
        let addition = multiplication.partialValue.addingReportingOverflow(1442695040888963407)
        state = addition.partialValue
        return state
    }

    public mutating func below(_ upperBound: UInt64) throws(RandomError) -> UInt64 {
        if upperBound == 0 {
            throw .zeroUpperBound
        }
        return next() % upperBound
    }
}

public struct PropertyGenerator<Value: Sendable>: Sendable {
    private let generateValue: @Sendable (inout DeterministicRandom) throws(RandomError) -> Value

    public init(
        _ generateValue: @escaping @Sendable (inout DeterministicRandom) throws(RandomError) -> Value
    ) {
        self.generateValue = generateValue
    }

    public func generate(using random: inout DeterministicRandom) throws(RandomError) -> Value {
        try generateValue(&random)
    }
}

extension PropertyGenerator where Value == Int {
    public static func integers(in range: ClosedRange<Int>) throws(RandomError) -> PropertyGenerator<Int> {
        if range.lowerBound > range.upperBound {
            throw .invalidRange
        }
        let distance = range.upperBound.subtractingReportingOverflow(range.lowerBound)
        if distance.overflow {
            throw .invalidRange
        }
        let width = distance.partialValue.addingReportingOverflow(1)
        if width.overflow || width.partialValue <= 0 {
            throw .invalidRange
        }
        return PropertyGenerator<Int> { (random: inout DeterministicRandom) throws(RandomError) -> Int in
            let offset = try random.below(UInt64(width.partialValue))
            let converted = Int(offset)
            let value = range.lowerBound.addingReportingOverflow(converted)
            if value.overflow {
                throw RandomError.invalidRange
            }
            return value.partialValue
        }
    }
}

public struct PropertyShrinker<Value: Sendable>: Sendable {
    private let shrinkValue: @Sendable (Value) -> [Value]

    public init(_ shrinkValue: @escaping @Sendable (Value) -> [Value]) {
        self.shrinkValue = shrinkValue
    }

    public func candidates(for value: Value) -> [Value] {
        shrinkValue(value)
    }
}

extension PropertyShrinker where Value == Int {
    public static let towardZero = PropertyShrinker<Int> { value in
        if value == 0 {
            return []
        }
        let half = value / 2
        if half == 0 {
            return [0]
        }
        return [0, half]
    }
}

public enum PropertyResult<Value: Sendable>: Sendable {
    case passed(IterationCount)
    case failed(value: Value, iteration: IterationCount)
}

public enum PropertyRunner {
    public static func check<Value: Sendable>(
        iterations: IterationCount,
        seed: UInt64,
        generator: PropertyGenerator<Value>,
        shrinker: PropertyShrinker<Value>,
        predicate: @Sendable (Value) -> Bool
    ) throws(RandomError) -> PropertyResult<Value> {
        var random = DeterministicRandom(seed: seed)
        for offset in 0..<iterations.rawValue {
            let value = try generator.generate(using: &random)
            if !predicate(value) {
                var minimal = value
                var searching = true
                while searching {
                    searching = false
                    for candidate in shrinker.candidates(for: minimal) where !predicate(candidate) {
                        minimal = candidate
                        searching = true
                        break
                    }
                }
                let iteration: IterationCount
                do {
                    iteration = try .positive(offset + 1)
                } catch {
                    throw .invalidRange
                }
                return .failed(value: minimal, iteration: iteration)
            }
        }
        return .passed(iterations)
    }
}
