import Foundation
import SwiftestModel
import SwiftestPlatform

public enum SwiftTestingExecutableError: Error, Equatable, Sendable {
    case platform(PlatformError)
    case stream(SwiftTestingStreamError)
    case duplicateEventOutputArgument
    case noExecutedTests
    case exitDisagreesWithEvents(Int32)
}

public struct SwiftTestingExecutableResult: Equatable, Sendable {
    public let summary: SwiftTestingRunSummary
    public let exitCode: Int32

    public init(summary: SwiftTestingRunSummary, exitCode: Int32) {
        self.summary = summary
        self.exitCode = exitCode
    }
}

public enum SwiftTestingExecutableDriver {
    public static func run(
        executable: String,
        arguments: [String],
        workingDirectory: String,
        scratchParent: String
    ) throws(SwiftTestingExecutableError) -> SwiftTestingExecutableResult {
        if arguments.contains("--event-stream-output-path") {
            throw .duplicateEventOutputArgument
        }
        let scratch: ScratchDirectoryOwner
        do {
            scratch = try ScratchDirectoryOwner(
                parent: scratchParent,
                name: "swiftest-events-" + String(PlatformClock.monotonicNanoseconds().rawValue)
            )
        } catch let error {
            throw .platform(error)
        }
        let eventPath = scratch.path + "/testing.jsonl"
        let exitCode: Int32
        do {
            let output = try ProcessBoundary.run(
                executable: executable,
                arguments: arguments + ["--event-stream-output-path", eventPath],
                workingDirectory: workingDirectory
            )
            exitCode = output.exitCode
        } catch let error {
            switch error {
            case .processExit(_, let code, _):
                exitCode = code
            default:
                throw .platform(error)
            }
        }
        let data: Data
        do {
            data = try FileSystemBoundary.read(path: eventPath)
        } catch let error {
            throw .platform(error)
        }
        let records: [SwiftTestingRecord]
        let summary: SwiftTestingRunSummary
        do {
            records = try StableTestingABI.decodeStream(data)
            summary = try StableTestingABI.summarize(records)
        } catch let error {
            throw .stream(error)
        }
        let noExecutedTests = summary.passed.rawValue == 0
            && summary.failed.rawValue == 0
            && summary.cancelled.rawValue == 0
        if noExecutedTests {
            throw .noExecutedTests
        }
        let unsuccessful = summary.failed.rawValue > 0
            || summary.cancelled.rawValue > 0
            || summary.runIssues.rawValue > 0
        if (exitCode == 0 && unsuccessful) || (exitCode != 0 && !unsuccessful) {
            throw .exitDisagreesWithEvents(exitCode)
        }
        return SwiftTestingExecutableResult(summary: summary, exitCode: exitCode)
    }
}
