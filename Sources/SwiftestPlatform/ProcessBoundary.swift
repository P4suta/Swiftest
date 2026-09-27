import Foundation
import SwiftestModel

public struct ProcessOutput: Equatable, Sendable {
    public let standardOutput: String
    public let standardError: String
    public let exitCode: Int32

    public init(standardOutput: String, standardError: String, exitCode: Int32) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.exitCode = exitCode
    }

    public var failureDetail: String {
        "stdout-bytes=" + String(standardOutput.utf8.count) + "\n"
            + standardOutput + "\nstderr-bytes=" + String(standardError.utf8.count) + "\n"
            + standardError
    }
}

public enum ProcessCancellationState: Sendable {
    case active
    case requested
}

public struct ProcessRunControl: Sendable {
    public let maximumDuration: DurationNanoseconds
    let cancellation: @Sendable () -> ProcessCancellationState

    public init(
        maximumDuration: DurationNanoseconds,
        cancellation: @escaping @Sendable () -> ProcessCancellationState
    ) {
        self.maximumDuration = maximumDuration
        self.cancellation = cancellation
    }

    public static let standard = ProcessRunControl(
        maximumDuration: .measured(3_600_000_000_000),
        cancellation: { Task.isCancelled ? .requested : .active }
    )
}

#if os(macOS)
private struct ProcessCapture: ~Copyable {
    let handle: FileHandle
    let path: String

    init(directory: String) throws(PlatformError) {
        guard let created = ABIAdapter.createTemporaryCapture(in: directory) else {
            throw .write(directory)
        }
        self.handle = FileHandle(fileDescriptor: created.descriptor, closeOnDealloc: false)
        self.path = created.path
    }

    borrowing func byteCount() throws(PlatformError) -> UInt64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            guard let size = attributes[.size] as? NSNumber else {
                throw PlatformError.read(path)
            }
            return size.uint64Value
        } catch {
            throw .read(path)
        }
    }

    borrowing func read(maximumBytes: Int) throws(PlatformError) -> Data {
        do {
            try handle.seek(toOffset: 0)
            var data = Data()
            while data.count <= maximumBytes {
                let remaining = maximumBytes + 1 - data.count
                guard let next = try handle.read(upToCount: min(remaining, 65_536)), !next.isEmpty else {
                    return data
                }
                data.append(next)
            }
            throw PlatformError.processOutputLimit(path)
        } catch let error as PlatformError {
            throw error
        } catch {
            throw .read(path)
        }
    }

    deinit {
        ABIAdapter.closeOrTerminate(handle.fileDescriptor)
        ABIAdapter.unlinkOrTerminate(path)
    }
}

public struct ProcessOwner: ~Copyable {
    private let process: Process
    private let outputCapture: ProcessCapture
    private let errorCapture: ProcessCapture
    private let inputPipe: Pipe?

    private static let maximumOutputBytes = 67_108_864
    private static let maximumStandardInputBytes = 4_096
    private static let pollingInterval = 0.01
    private static let terminationGraceNanoseconds: UInt64 = 250_000_000

    init(
        executable: String,
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String],
        captureDirectory: String,
        standardInput: Data? = nil
    ) throws(PlatformError) {
        if let standardInput, standardInput.count > Self.maximumStandardInputBytes {
            throw .processInputLimit(executable)
        }
        let process = Process()
        let outputCapture = try ProcessCapture(directory: captureDirectory)
        let errorCapture = try ProcessCapture(directory: captureDirectory)
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        process.standardOutput = outputCapture.handle
        process.standardError = errorCapture.handle
        let inputPipe: Pipe?
        if let standardInput {
            let pipe = Pipe()
            do {
                try pipe.fileHandleForWriting.write(contentsOf: standardInput)
                try pipe.fileHandleForWriting.close()
            } catch {
                throw .write(executable)
            }
            process.standardInput = pipe.fileHandleForReading
            inputPipe = pipe
        } else {
            inputPipe = nil
        }
        self.process = process
        self.outputCapture = outputCapture
        self.errorCapture = errorCapture
        self.inputPipe = inputPipe
    }

    consuming func run(control: ProcessRunControl) throws(PlatformError) -> ProcessOutput {
        let executable: String
        if let path = process.executableURL?.path {
            executable = path
        } else {
            executable = "process"
        }
        if control.cancellation() == .requested {
            throw .processCancelled(executable)
        }
        if control.maximumDuration.rawValue == 0 {
            throw .processTimedOut(executable)
        }
        do {
            try process.run()
        } catch {
            throw .processLaunch(executable)
        }
        let started = PlatformClock.monotonicNanoseconds().rawValue
        while process.isRunning {
            if control.cancellation() == .requested {
                try stopAndReap(executable: executable)
                throw .processCancelled(executable)
            }
            let now = PlatformClock.monotonicNanoseconds().rawValue
            if now < started || now - started >= control.maximumDuration.rawValue {
                try stopAndReap(executable: executable)
                throw .processTimedOut(executable)
            }
            let outputBytes = try outputCapture.byteCount()
            let errorBytes = try errorCapture.byteCount()
            if outputBytes > UInt64(Self.maximumOutputBytes)
                || errorBytes > UInt64(Self.maximumOutputBytes) {
                try stopAndReap(executable: executable)
                throw .processOutputLimit(executable)
            }
            Thread.sleep(forTimeInterval: Self.pollingInterval)
        }
        let ended = PlatformClock.monotonicNanoseconds().rawValue
        process.waitUntilExit()
        if ended < started || ended - started >= control.maximumDuration.rawValue {
            throw .processTimedOut(executable)
        }
        let outputData = try outputCapture.read(maximumBytes: Self.maximumOutputBytes)
        let errorData = try errorCapture.read(maximumBytes: Self.maximumOutputBytes)
        guard let text = String(data: outputData, encoding: .utf8),
            let errorText = String(data: errorData, encoding: .utf8) else {
            throw .invalidOutput(executable)
        }
        return ProcessOutput(
            standardOutput: text,
            standardError: errorText,
            exitCode: process.terminationStatus
        )
    }

    private borrowing func stopAndReap(executable: String) throws(PlatformError) {
        if process.isRunning && !ABIAdapter.requestTermination(process.processIdentifier) {
            throw .processTerminationFailed(executable)
        }
        let started = PlatformClock.monotonicNanoseconds().rawValue
        while process.isRunning {
            let now = PlatformClock.monotonicNanoseconds().rawValue
            if now < started || now - started >= Self.terminationGraceNanoseconds {
                break
            }
            Thread.sleep(forTimeInterval: Self.pollingInterval)
        }
        if process.isRunning && !ABIAdapter.forceKill(process.processIdentifier) {
            throw .processTerminationFailed(executable)
        }
        let killedAt = PlatformClock.monotonicNanoseconds().rawValue
        while process.isRunning {
            let now = PlatformClock.monotonicNanoseconds().rawValue
            if now < killedAt || now - killedAt >= Self.terminationGraceNanoseconds {
                throw .processTerminationFailed(executable)
            }
            Thread.sleep(forTimeInterval: Self.pollingInterval)
        }
        process.waitUntilExit()
    }

    deinit {
        if process.isRunning {
            if !ABIAdapter.forceKill(process.processIdentifier) {
                ABIAdapter.terminateCleanupFailure()
            }
            let started = PlatformClock.monotonicNanoseconds().rawValue
            while process.isRunning {
                let now = PlatformClock.monotonicNanoseconds().rawValue
                if now < started || now - started >= Self.terminationGraceNanoseconds {
                    ABIAdapter.terminateCleanupFailure()
                }
                Thread.sleep(forTimeInterval: Self.pollingInterval)
            }
            process.waitUntilExit()
        }
    }
}
#else
public struct ProcessOwner: ~Copyable {
    private let executable: String

    init(
        executable: String,
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String],
        captureDirectory: String,
        standardInput: Data? = nil
    ) throws(PlatformError) {
        self.executable = executable
    }

    consuming func run(control: ProcessRunControl) throws(PlatformError) -> ProcessOutput {
        throw .unsupportedPlatform(executable)
    }
}
#endif

public enum ProcessBoundary {
    public static func run(
        executable: String,
        arguments: [String],
        workingDirectory: String?
    ) throws(PlatformError) -> ProcessOutput {
        try run(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            control: .standard
        )
    }

    public static func run(
        executable: String,
        arguments: [String],
        workingDirectory: String?,
        control: ProcessRunControl
    ) throws(PlatformError) -> ProcessOutput {
        let scratch = try ScratchDirectoryOwner(
            parent: "/private/tmp",
            name: "swiftest-process-" + String(PlatformClock.monotonicNanoseconds().rawValue)
        )
        return try launch(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: ProcessInfo.processInfo.environment,
            captureDirectory: try CanonicalPathBoundary.directory(scratch.path),
            control: control
        )
    }

    public static func runPinnedApple(
        executable: String,
        arguments: [String],
        workingDirectory: String,
        scratch: borrowing ScratchDirectoryOwner
    ) throws(PlatformError) -> ProcessOutput {
        let temporary = scratch.path + "/temporary"
        let moduleCache = scratch.path + "/module-cache"
        do {
            try FileManager.default.createDirectory(atPath: temporary, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(atPath: moduleCache, withIntermediateDirectories: true)
        } catch {
            throw .createDirectory(scratch.path)
        }
        let canonicalScratch = try CanonicalPathBoundary.directory(scratch.path)
        let canonicalTemporary = try CanonicalPathBoundary.directory(temporary)
        let canonicalModuleCache = try CanonicalPathBoundary.directory(moduleCache)
        guard canonicalTemporary == canonicalScratch + "/temporary",
            canonicalModuleCache == canonicalScratch + "/module-cache" else {
            throw .pathEscapesRoot(scratch.path)
        }
        return try launch(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: [
                "CLANG_MODULE_CACHE_PATH": moduleCache,
                "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer",
                "HOME": scratch.path,
                "LANG": "C",
                "LC_ALL": "C",
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Xcode.app/Contents/Developer/usr/bin",
                "SWIFTPM_MODULECACHE_OVERRIDE": moduleCache,
                "TMPDIR": temporary,
            ],
            captureDirectory: canonicalScratch,
            control: .standard
        )
    }

    public static func runPinnedLean(
        toolchainBin: String,
        executable: String,
        arguments: [String],
        workingDirectory: String,
        scratch: borrowing ScratchDirectoryOwner,
        standardInput: Data? = nil
    ) throws(PlatformError) -> ProcessOutput {
        let bin = try CanonicalPathBoundary.captureDirectoryIdentity(toolchainBin)
        guard bin.canonicalPath == toolchainBin,
            ["lake", "lean", "leanchecker"].contains(where: { executable == toolchainBin + "/" + $0 }),
            try FileSystemBoundary.entryKind(path: executable) == .file,
            try CanonicalPathBoundary.existing(executable) == executable else {
            throw .invalidRoot(executable)
        }
        try bin.verifyCurrentLocation()
        let canonicalScratch = try CanonicalPathBoundary.directory(scratch.path)
        let temporary = scratch.path + "/temporary"
        do {
            try FileManager.default.createDirectory(atPath: temporary, withIntermediateDirectories: true)
        } catch {
            throw .createDirectory(temporary)
        }
        guard try CanonicalPathBoundary.directory(temporary) == canonicalScratch + "/temporary" else {
            throw .pathEscapesRoot(temporary)
        }
        return try launch(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: [
                "HOME": scratch.path,
                "LANG": "C",
                "LC_ALL": "C",
                "PATH": toolchainBin + ":/usr/bin:/bin",
                "TMPDIR": temporary,
            ],
            captureDirectory: canonicalScratch,
            standardInput: standardInput,
            control: .standard
        )
    }

    private static func launch(
        executable: String,
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String],
        captureDirectory: String,
        standardInput: Data? = nil,
        control: ProcessRunControl
    ) throws(PlatformError) -> ProcessOutput {
        let owner = try ProcessOwner(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            captureDirectory: captureDirectory,
            standardInput: standardInput
        )
        let output = try owner.run(control: control)
        if output.exitCode != 0 {
            throw .processExit(executable, output.exitCode, output.failureDetail)
        }
        return output
    }
}
