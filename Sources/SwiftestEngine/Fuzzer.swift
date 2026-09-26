import Foundation
import SwiftestModel

public enum FuzzError: Error, Equatable, Sendable {
    case emptyCorpus
    case random(RandomError)
}

public enum FuzzOutcome: Equatable, Sendable {
    case accepted
    case rejected
    case crashed(Diagnostic)
}

public struct FuzzFinding: Equatable, Sendable {
    public let input: Data
    public let outcome: FuzzOutcome
    public let iteration: IterationCount

    public init(input: Data, outcome: FuzzOutcome, iteration: IterationCount) {
        self.input = input
        self.outcome = outcome
        self.iteration = iteration
    }
}

public enum DeterministicFuzzer {
    public static func run(
        corpus: [Data],
        iterations: IterationCount,
        seed: UInt64,
        oracle: @Sendable (Data) -> FuzzOutcome
    ) throws(FuzzError) -> [FuzzFinding] {
        if corpus.isEmpty {
            throw .emptyCorpus
        }
        var random = DeterministicRandom(seed: seed)
        var findings: [FuzzFinding] = []
        for offset in 0..<iterations.rawValue {
            let corpusIndex: Int
            do {
                corpusIndex = Int(try random.below(UInt64(corpus.count)))
            } catch let error {
                throw .random(error)
            }
            var bytes = Array(corpus[corpusIndex])
            if bytes.isEmpty {
                bytes.append(0)
            }
            let byteIndex: Int
            let replacement: UInt8
            do {
                byteIndex = Int(try random.below(UInt64(bytes.count)))
                replacement = UInt8(try random.below(256))
            } catch let error {
                throw .random(error)
            }
            bytes[byteIndex] = replacement
            let input = Data(bytes)
            let outcome = oracle(input)
            if case .crashed = outcome {
                let iteration: IterationCount
                do {
                    iteration = try .positive(offset + 1)
                } catch {
                    throw .random(.invalidRange)
                }
                findings.append(FuzzFinding(input: input, outcome: outcome, iteration: iteration))
            }
        }
        return findings
    }
}
