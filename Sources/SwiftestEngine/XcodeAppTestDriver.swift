import Foundation
import SwiftestModel
import SwiftestPlatform

public enum XcodeAppTestError: Error, Equatable, Sendable {
    case platform(PlatformError)
    case bridge(AppleTestBridgeError)
    case summary(XCResultSummaryError)
    case coverage(XCCoverageError)
    case digest(DigestError)
    case inputClosure(XcodeInputClosureError)
    case invalidContainer(String)
    case ambiguousContainer(String)
    case invalidScheme
    case invalidDestination
    case missingXctestrun
    case ambiguousXctestrun
    case invalidXctestrunVersion(String)
    case noExecutedTests
    case exitDisagreesWithSummary(Int32)
}

public enum XcodeContainerKind: Equatable, Sendable {
    case project
    case workspace
}

public struct XcodeContainer: Equatable, Sendable {
    public let path: String
    public let kind: XcodeContainerKind

    private init(path: String, kind: XcodeContainerKind) {
        self.path = path
        self.kind = kind
    }

    public static func project(_ path: String) throws(XcodeAppTestError) -> XcodeContainer {
        try make(path: path, suffix: ".xcodeproj", kind: .project)
    }

    public static func workspace(_ path: String) throws(XcodeAppTestError) -> XcodeContainer {
        try make(path: path, suffix: ".xcworkspace", kind: .workspace)
    }

    public static func discover(root: String) throws(XcodeAppTestError) -> XcodeContainer {
        let entries: [String]
        do {
            entries = try FileSystemBoundary.list(path: root)
        } catch let error {
            throw .platform(error)
        }
        let workspaces = entries.filter { $0.hasSuffix(".xcworkspace") }
        if workspaces.count > 1 {
            throw .ambiguousContainer(root)
        }
        if let workspace = workspaces.first {
            return try .workspace(root + "/" + workspace)
        }
        let projects = entries.filter { $0.hasSuffix(".xcodeproj") }
        if projects.count > 1 {
            throw .ambiguousContainer(root)
        }
        guard let project = projects.first else {
            throw .invalidContainer(root)
        }
        return try .project(root + "/" + project)
    }

    private static func make(
        path: String,
        suffix: String,
        kind: XcodeContainerKind
    ) throws(XcodeAppTestError) -> XcodeContainer {
        guard path.hasSuffix(suffix) else {
            throw .invalidContainer(path)
        }
        let entry: FileEntryKind
        do {
            entry = try FileSystemBoundary.entryKind(path: path)
        } catch {
            throw .invalidContainer(path)
        }
        guard entry == .directory else {
            throw .invalidContainer(path)
        }
        return XcodeContainer(path: URL(fileURLWithPath: path).standardizedFileURL.path, kind: kind)
    }
}

public struct XcodeAppTestResult: Equatable, Sendable {
    public let summary: XCResultSummary
    public let coverage: XCCoverageReport
    public let summaryDigest: Digest
    public let coverageDigest: Digest
    public let exitCode: Int32

    public init(
        summary: XCResultSummary,
        coverage: XCCoverageReport,
        summaryDigest: Digest,
        coverageDigest: Digest,
        exitCode: Int32
    ) {
        self.summary = summary
        self.coverage = coverage
        self.summaryDigest = summaryDigest
        self.coverageDigest = coverageDigest
        self.exitCode = exitCode
    }
}

public enum XcodeAppTestDriver {
    public static func run(
        container: XcodeContainer,
        scheme: String,
        destination: String,
        workingDirectory: String,
        scratchParent: String
    ) throws(XcodeAppTestError) -> XcodeAppTestResult {
        if scheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw .invalidScheme
        }
        if destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw .invalidDestination
        }
        do {
            try XcodeInputClosure.verify(
                container: container,
                repositoryRoot: workingDirectory,
                scheme: scheme
            )
        } catch let error {
            throw .inputClosure(error)
        }
        let scratch: ScratchDirectoryOwner
        do {
            scratch = try ScratchDirectoryOwner(
                parent: scratchParent,
                name: "swiftest-xcode-" + String(PlatformClock.monotonicNanoseconds().rawValue)
            )
        } catch let error {
            throw .platform(error)
        }
        let derivedData = scratch.path + "/DerivedData"
        let buildBundle = scratch.path + "/Build.xcresult"
        let resultBundle = scratch.path + "/Test.xcresult"
        let build = buildInvocation(
            container: container,
            scheme: scheme,
            destination: destination,
            derivedData: derivedData,
            resultBundle: buildBundle,
            workingDirectory: workingDirectory
        )
        let buildOutput: ProcessOutput
        do {
            buildOutput = try XcodeTestDriver.run(build)
        } catch let error {
            throw .bridge(error)
        }
        if buildOutput.exitCode != 0 {
            throw .exitDisagreesWithSummary(buildOutput.exitCode)
        }
        let xctestrun = try findXctestrun(products: derivedData + "/Build/Products")
        try validateXctestrunVersion(path: xctestrun, workingDirectory: workingDirectory)
        let test = testInvocation(
            xctestrun: xctestrun,
            destination: destination,
            resultBundle: resultBundle,
            workingDirectory: workingDirectory
        )
        let exitCode: Int32
        do {
            let output = try XcodeTestDriver.run(test)
            exitCode = output.exitCode
        } catch let error {
            switch error {
            case .platform(.processExit(_, let code, _)):
                exitCode = code
            default:
                throw .bridge(error)
            }
        }
        let summaryOutput: ProcessOutput
        do {
            summaryOutput = try XcodeTestDriver.run(XcodeTestDriver.invocation(
                action: .resultSummary(resultBundle: resultBundle),
                workingDirectory: workingDirectory
            ))
        } catch let error {
            throw .bridge(error)
        }
        let summaryData = Data(summaryOutput.standardOutput.utf8)
        let summary: XCResultSummary
        do {
            summary = try XCResultSummary.decode(summaryData)
        } catch let error {
            throw .summary(error)
        }
        if summary.total.rawValue == summary.skipped.rawValue {
            throw .noExecutedTests
        }
        if (exitCode == 0 && summary.result == .failed)
            || (exitCode != 0 && summary.result != .failed) {
            throw .exitDisagreesWithSummary(exitCode)
        }
        let coverageOutput: ProcessOutput
        do {
            coverageOutput = try XcodeTestDriver.run(XcodeTestDriver.invocation(
                action: .coverage(resultBundle: resultBundle),
                workingDirectory: workingDirectory
            ))
        } catch let error {
            throw .bridge(error)
        }
        let coverageData = Data(coverageOutput.standardOutput.utf8)
        let coverage: XCCoverageReport
        do {
            coverage = try XCCoverageReport.decode(coverageData)
        } catch let error {
            throw .coverage(error)
        }
        let summaryDigest: Digest
        let coverageDigest: Digest
        do {
            summaryDigest = try .sha256(summaryData)
            coverageDigest = try .sha256(coverageData)
        } catch let error {
            throw .digest(error)
        }
        return XcodeAppTestResult(
            summary: summary,
            coverage: coverage,
            summaryDigest: summaryDigest,
            coverageDigest: coverageDigest,
            exitCode: exitCode
        )
    }

    static func buildInvocation(
        container: XcodeContainer,
        scheme: String,
        destination: String,
        derivedData: String,
        resultBundle: String,
        workingDirectory: String
    ) -> XcodeInvocation {
        let selection: [String]
        switch container.kind {
        case .project:
            selection = ["-project", container.path]
        case .workspace:
            selection = ["-workspace", container.path]
        }
        return XcodeInvocation(
            executable: "/usr/bin/xcrun",
            arguments: ["xcodebuild"] + selection + [
                "-scheme", scheme,
                "-destination", destination,
                "-derivedDataPath", derivedData,
                "-resultBundlePath", resultBundle,
                "-enableCodeCoverage", "YES",
                "build-for-testing",
            ],
            workingDirectory: workingDirectory
        )
    }

    static func testInvocation(
        xctestrun: String,
        destination: String,
        resultBundle: String,
        workingDirectory: String
    ) -> XcodeInvocation {
        XcodeInvocation(
            executable: "/usr/bin/xcrun",
            arguments: [
                "xcodebuild",
                "-xctestrun", xctestrun,
                "-destination", destination,
                "-resultBundlePath", resultBundle,
                "-enableCodeCoverage", "YES",
                "test-without-building",
            ],
            workingDirectory: workingDirectory
        )
    }

    static func findXctestrun(products: String) throws(XcodeAppTestError) -> String {
        let entries: [String]
        do {
            entries = try FileSystemBoundary.list(path: products)
        } catch let error {
            throw .platform(error)
        }
        let candidates = entries.filter { $0.hasSuffix(".xctestrun") }
        if candidates.count > 1 {
            throw .ambiguousXctestrun
        }
        guard let name = candidates.first else {
            throw .missingXctestrun
        }
        let path = products + "/" + name
        let entry: FileEntryKind
        do {
            entry = try FileSystemBoundary.entryKind(path: path)
        } catch let error {
            throw .platform(error)
        }
        guard entry == .file else {
            throw .missingXctestrun
        }
        return path
    }

    static func validateXctestrunVersion(
        path: String,
        workingDirectory: String
    ) throws(XcodeAppTestError) {
        let invocation = XcodeInvocation(
            executable: "/usr/bin/plutil",
            arguments: [
                "-extract", "__xctestrun_metadata__.FormatVersion",
                "raw", "-o", "-", path,
            ],
            workingDirectory: workingDirectory
        )
        let output: ProcessOutput
        do {
            output = try XcodeTestDriver.run(invocation)
        } catch {
            throw .invalidXctestrunVersion(path)
        }
        if output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) != "2" {
            throw .invalidXctestrunVersion(path)
        }
    }
}
