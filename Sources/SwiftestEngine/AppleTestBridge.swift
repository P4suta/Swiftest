import Foundation
import SwiftestModel
import SwiftestPlatform

public enum AppleTestBridgeError: Error, Equatable, Sendable {
    case platform(PlatformError)
    case sourceChanged(String)
    case digest(DigestError)
}

public enum StableTestingABI {}

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

    public static func run(_ invocation: XcodeInvocation) throws(AppleTestBridgeError) -> ProcessOutput {
        do {
            return try ProcessBoundary.run(
                executable: invocation.executable,
                arguments: invocation.arguments,
                workingDirectory: invocation.workingDirectory
            )
        } catch let error {
            throw .platform(error)
        }
    }
}

public struct SourceSeal: Equatable, Sendable {
    public let digests: [String: Digest]

    public init(digests: [String: Digest]) {
        self.digests = digests
    }
}

public enum SourceIntegrity {
    public static func capture(paths: [String]) throws(AppleTestBridgeError) -> SourceSeal {
        var digests: [String: Digest] = [:]
        for path in paths.sorted() {
            let data: Data
            do {
                data = try FileSystemBoundary.read(path: path)
            } catch let error {
                throw .platform(error)
            }
            do {
                digests[path] = try Digest.sha256(data)
            } catch let error {
                throw .digest(error)
            }
        }
        return SourceSeal(digests: digests)
    }

    public static func verify(_ seal: SourceSeal) throws(AppleTestBridgeError) {
        let current = try capture(paths: Array(seal.digests.keys))
        for (path, digest) in seal.digests {
            if current.digests[path] != digest {
                throw .sourceChanged(path)
            }
        }
    }
}
