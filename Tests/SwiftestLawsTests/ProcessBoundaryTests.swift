import Foundation
import SwiftestModel
@testable import SwiftestPlatform
import Testing

#if os(macOS)
@Test
func processOwnerSuppliesTrustedStandardInputWithoutAFilesystemPath() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-process-input-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let input = Data(repeating: 65, count: 4_096)
    let owner = try ProcessOwner(
        executable: "/bin/cat",
        arguments: [],
        workingDirectory: nil,
        environment: [:],
        captureDirectory: scratch.path,
        standardInput: input
    )
    let output = try owner.run(control: .standard)
    #expect(output.standardOutput == String(decoding: input, as: UTF8.self))
    #expect(output.standardError.isEmpty)
    #expect(throws: PlatformError.processInputLimit("/bin/cat")) {
        let oversized = try ProcessOwner(
            executable: "/bin/cat",
            arguments: [],
            workingDirectory: nil,
            environment: [:],
            captureDirectory: scratch.path,
            standardInput: Data(repeating: 65, count: 4_097)
        )
        let unexpected = try oversized.run(control: .standard)
        Issue.record("oversized process input accepted: \(unexpected.standardOutput.utf8.count) bytes")
    }
}
#endif

@Test
func processDeadlineEscalatesPastIgnoredTerminationAndReaps() throws {
    let started = PlatformClock.monotonicNanoseconds().rawValue
    let control = ProcessRunControl(
        maximumDuration: .measured(40_000_000),
        cancellation: { .active }
    )
    do {
        let output = try ProcessBoundary.run(
            executable: "/bin/sh",
            arguments: ["-c", "trap '' TERM; while :; do :; done"],
            workingDirectory: nil,
            control: control
        )
        Issue.record("a nonterminating process returned successfully")
        #expect(output.exitCode != 0)
    } catch let error {
        #expect(error == .processTimedOut("/bin/sh"))
    }
    let elapsed = PlatformClock.monotonicNanoseconds().rawValue - started
    #expect(elapsed < 2_000_000_000)
}

@Test
func processCancellationSuppressesAndReapsTheRealOperation() throws {
    let started = PlatformClock.monotonicNanoseconds().rawValue
    let control = ProcessRunControl(
        maximumDuration: .measured(5_000_000_000),
        cancellation: {
            let now = PlatformClock.monotonicNanoseconds().rawValue
            return now >= started && now - started >= 50_000_000 ? .requested : .active
        }
    )
    do {
        let output = try ProcessBoundary.run(
            executable: "/bin/sleep",
            arguments: ["5"],
            workingDirectory: nil,
            control: control
        )
        Issue.record("a cancelled process returned successfully")
        #expect(output.exitCode != 0)
    } catch let error {
        #expect(error == .processCancelled("/bin/sleep"))
    }
    let elapsed = PlatformClock.monotonicNanoseconds().rawValue - started
    #expect(elapsed < 2_000_000_000)
}

@Test
func prelaunchCancellationDoesNotStartAnExecutable() throws {
    let control = ProcessRunControl(
        maximumDuration: .measured(5_000_000_000),
        cancellation: { .requested }
    )
    do {
        let output = try ProcessBoundary.run(
            executable: "/bin/sleep",
            arguments: ["5"],
            workingDirectory: nil,
            control: control
        )
        Issue.record("prelaunch cancellation started the process")
        #expect(output.exitCode != 0)
    } catch let error {
        #expect(error == .processCancelled("/bin/sleep"))
    }
}

@Test
func zeroProcessDeadlineDoesNotStartAnExecutable() throws {
    let control = ProcessRunControl(
        maximumDuration: .measured(0),
        cancellation: { .active }
    )
    do {
        let output = try ProcessBoundary.run(
            executable: "/bin/sleep",
            arguments: ["5"],
            workingDirectory: nil,
            control: control
        )
        Issue.record("zero deadline started the process")
        #expect(output.exitCode != 0)
    } catch let error {
        #expect(error == .processTimedOut("/bin/sleep"))
    }
}

@Test
func inheritedStandardOutputDoesNotHoldTheOwnerOpen() throws {
    let started = PlatformClock.monotonicNanoseconds().rawValue
    let control = ProcessRunControl(
        maximumDuration: .measured(500_000_000),
        cancellation: { .active }
    )
    let output = try ProcessBoundary.run(
        executable: "/bin/sh",
        arguments: ["-c", "sleep 2 & printf 'ready\\n'"],
        workingDirectory: nil,
        control: control
    )
    #expect(output.standardOutput == "ready\n")
    #expect(output.standardError.isEmpty)
    let elapsed = PlatformClock.monotonicNanoseconds().rawValue - started
    #expect(elapsed < 1_000_000_000)
}
