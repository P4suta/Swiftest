import Foundation
import SwiftestCodec
import SwiftestModel
import SwiftestPlatform

public enum AppleTestBridgeError: Error, Equatable, Sendable {
    case platform(PlatformError)
    case codec(StrictJSONError)
    case identifier(IdentifierError)
    case schema(NumericValueError)
    case unsupportedSchema(SchemaVersion)
    case invalidEventKind(String)
    case invalidDuration(Int)
    case sourceChanged(String)
    case digest(DigestError)
}

public enum StableTestEventKind: String, CaseIterable, Sendable {
    case discovered
    case started
    case passed
    case failed
    case skipped
}

public struct StableTestEvent: Equatable, Sendable {
    public let schema: SchemaVersion
    public let kind: StableTestEventKind
    public let test: TestID
    public let duration: DurationNanoseconds

    public init(
        schema: SchemaVersion,
        kind: StableTestEventKind,
        test: TestID,
        duration: DurationNanoseconds
    ) {
        self.schema = schema
        self.kind = kind
        self.test = test
        self.duration = duration
    }
}

public enum StableTestingABI {
    public static func decodeEvent(_ data: Data) throws(AppleTestBridgeError) -> StableTestEvent {
        let value: JSONValue
        do {
            value = try StrictJSON.decode(data)
        } catch let error {
            throw .codec(error)
        }
        var reader: JSONObjectReader
        do {
            reader = try JSONObjectReader(value)
        } catch let error {
            throw .codec(error)
        }
        let schemaRaw: Int
        let kindRaw: String
        let testRaw: String
        let durationRaw: Int
        do {
            schemaRaw = try reader.requiredInteger("schema")
            kindRaw = try reader.requiredString("kind")
            testRaw = try reader.requiredString("test")
            durationRaw = try reader.requiredInteger("durationNanoseconds")
            try reader.finish()
        } catch let error {
            throw .codec(error)
        }
        let schema: SchemaVersion
        do {
            schema = try SchemaVersion.parse(schemaRaw)
        } catch let error {
            throw .schema(error)
        }
        if schema != .v1 {
            throw .unsupportedSchema(schema)
        }
        guard let kind = StableTestEventKind(rawValue: kindRaw) else {
            throw .invalidEventKind(kindRaw)
        }
        let test: TestID
        do {
            test = try TestID.parse(testRaw)
        } catch let error {
            throw .identifier(error)
        }
        if durationRaw < 0 {
            throw .invalidDuration(durationRaw)
        }
        return StableTestEvent(
            schema: schema,
            kind: kind,
            test: test,
            duration: .measured(UInt64(durationRaw))
        )
    }
}

public enum XcodeTestAction: Sendable {
    case buildForTesting
    case testWithoutBuilding(xctestrun: String)
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
        scheme: String,
        destination: String,
        resultBundle: String,
        workingDirectory: String
    ) -> XcodeInvocation {
        let arguments: [String]
        switch action {
        case .buildForTesting:
            arguments = [
                "xcodebuild",
                "-scheme", scheme,
                "-destination", destination,
                "-resultBundlePath", resultBundle,
                "build-for-testing",
            ]
        case .testWithoutBuilding(let xctestrun):
            arguments = [
                "xcodebuild",
                "-xctestrun", xctestrun,
                "-destination", destination,
                "-resultBundlePath", resultBundle,
                "test-without-building",
            ]
        case .resultSummary(let path):
            arguments = [
                "xcresulttool",
                "get", "test-results", "summary",
                "--path", path,
                "--format", "json",
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
