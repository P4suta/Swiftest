import Foundation
import SwiftestPlatform

public enum AppleTestBridgeError: Error, Equatable, Sendable {
    case platform(PlatformError)
}

public enum XcodeTestAction: Sendable {
    case resultSummary(resultBundle: String)
    case coverage(resultBundle: String)
}

public struct XcodeInvocation: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
    public let workingDirectory: String

    public init(executable: String, arguments: [String], workingDirectory: String) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
    }
}

public enum XcodeTestDriver {
    public static func invocation(
        action: XcodeTestAction,
        workingDirectory: String
    ) -> XcodeInvocation {
        let arguments: [String]
        switch action {
        case .resultSummary(let path):
            arguments = [
                "xcresulttool",
                "get", "test-results", "summary",
                "--path", path,
                "--schema-version", "0.4.0",
                "--compact",
            ]
        case .coverage(let path):
            arguments = [
                "xccov",
                "view",
                "--report",
                "--json",
                path,
            ]
        }
        return XcodeInvocation(
            executable: "/usr/bin/xcrun",
            arguments: arguments,
            workingDirectory: workingDirectory
        )
    }

    public static func run(
        _ invocation: XcodeInvocation,
        scratch: borrowing ScratchDirectoryOwner
    ) throws(AppleTestBridgeError) -> ProcessOutput {
        do {
            return try ProcessBoundary.runPinnedApple(
                executable: invocation.executable,
                arguments: invocation.arguments,
                workingDirectory: invocation.workingDirectory,
                scratch: scratch
            )
        } catch let error {
            throw .platform(error)
        }
    }
}
