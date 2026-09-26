import Foundation

public struct ProcessOutput: Equatable, Sendable {
    public let standardOutput: String
    public let exitCode: Int32

    public init(standardOutput: String, exitCode: Int32) {
        self.standardOutput = standardOutput
        self.exitCode = exitCode
    }
}

#if os(macOS)
public struct ProcessOwner: ~Copyable {
    private let process: Process
    private let output: Pipe

    init(executable: String, arguments: [String], workingDirectory: String?) {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        process.standardOutput = output
        process.standardError = output
        self.process = process
        self.output = output
    }

    consuming func run() throws(PlatformError) -> ProcessOutput {
        let executable: String
        if let path = process.executableURL?.path {
            executable = path
        } else {
            executable = "process"
        }
        do {
            try process.run()
        } catch {
            throw .processLaunch(executable)
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else {
            throw .invalidOutput(executable)
        }
        return ProcessOutput(standardOutput: text, exitCode: process.terminationStatus)
    }

    deinit {
        if process.isRunning {
            process.terminate()
        }
    }
}
#else
public struct ProcessOwner: ~Copyable {
    private let executable: String

    init(executable: String, arguments: [String], workingDirectory: String?) {
        self.executable = executable
    }

    consuming func run() throws(PlatformError) -> ProcessOutput {
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
        let owner = ProcessOwner(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory
        )
        let output = try owner.run()
        if output.exitCode != 0 {
            throw .processExit(executable, output.exitCode, output.standardOutput)
        }
        return output
    }
}
