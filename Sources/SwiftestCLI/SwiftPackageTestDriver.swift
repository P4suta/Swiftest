import Foundation
import Swiftest
import SwiftestCodec
import SwiftestPlatform

enum SwiftPackageTestError: Error {
    case notPackage(String)
    case platform(PlatformError)
    case missingResult(Int32)
    case invalidInventory(XUnitCodecError)
    case invalidStream(SwiftTestingStreamError)
}

struct SwiftPackageTestExecution {
    let resultDocuments: XUnitRunnerDocuments
    let discoveredTests: XUnitTestInventory
    let swiftTestingEvents: SwiftTestingCampaignEvidence
    let exitCode: Int32
}

enum TargetTestObservation {
    case notConfigured
    case passed(EvidenceCount, Digest)
    case failed(EvidenceCount, Digest)
    case apparatus(Diagnostic)

    var executionCount: EvidenceCount {
        switch self {
        case .notConfigured, .apparatus:
            return .zero
        case .passed(let count, _), .failed(let count, _):
            return count
        }
    }

    var resultDigest: Digest? {
        switch self {
        case .passed(_, let digest), .failed(_, let digest):
            return digest
        case .notConfigured, .apparatus:
            return nil
        }
    }
}

enum SwiftPackageTestDriver {
    static func observe(root: String) -> TargetTestObservation {
        let execution: SwiftPackageTestExecution
        do {
            execution = try execute(root: root)
        } catch let error {
            switch error {
            case .notPackage:
                return .notConfigured
            case .platform, .missingResult:
                return .apparatus(Diagnostic(
                    code: .apparatusFailed,
                    subject: "swift-package",
                    detail: "test runner did not yield complete evidence"
                ))
            case .invalidInventory:
                return .apparatus(Diagnostic(
                    code: .invalidWire,
                    subject: "swift-package-inventory",
                    detail: "malformed discovered test inventory"
                ))
            case .invalidStream:
                return .apparatus(Diagnostic(
                    code: .invalidWire,
                    subject: "swift-testing-events",
                    detail: "incomplete or malformed test lifecycle"
                ))
            }
        }
        let report: XUnitReport
        do {
            report = try XUnitCodec.decodeRunnerDocuments(execution.resultDocuments)
        } catch {
            return .apparatus(Diagnostic(
                code: .invalidWire,
                subject: "swift-package-xunit",
                detail: "malformed test result"
            ))
        }
        let xctestReport: XUnitReport
        do {
            xctestReport = try XUnitCodec.decode(execution.resultDocuments.xctest)
        } catch {
            return .apparatus(Diagnostic(
                code: .invalidWire,
                subject: "xctest-xunit",
                detail: "malformed XCTest result"
            ))
        }
        let swiftTestingReport: XUnitReport
        do {
            swiftTestingReport = try XUnitCodec.decode(execution.resultDocuments.swiftTesting)
        } catch {
            return .apparatus(Diagnostic(
                code: .invalidWire,
                subject: "swift-testing-xunit",
                detail: "malformed Swift Testing result"
            ))
        }
        do {
            try execution.discoveredTests.verify(xctest: xctestReport, swiftTesting: swiftTestingReport)
        } catch {
            return .apparatus(Diagnostic(
                code: .apparatusFailed,
                subject: "swift-package-inventory",
                detail: "discovered and executed tests disagree"
            ))
        }
        let events = execution.swiftTestingEvents.summary
        if events.parameterizedFunctions.rawValue > 0 {
            return .apparatus(Diagnostic(
                code: .apparatusFailed,
                subject: "swift-testing-cases",
                detail: "expected parameterized case cardinality unavailable"
            ))
        }
        let eventFailureCount = events.failed.rawValue
        let xunitFailureCount = swiftTestingReport.failures.rawValue.addingReportingOverflow(
            swiftTestingReport.errors.rawValue
        )
        let passedPlusFailed = events.passed.rawValue.addingReportingOverflow(xunitFailureCount.partialValue)
        let eventTerminalCount = passedPlusFailed.partialValue.addingReportingOverflow(
            swiftTestingReport.skipped.rawValue
        )
        if xunitFailureCount.overflow
            || passedPlusFailed.overflow
            || eventTerminalCount.overflow
            || events.discovered != swiftTestingReport.tests
            || eventTerminalCount.partialValue != swiftTestingReport.tests.rawValue
            || eventFailureCount != xunitFailureCount.partialValue
            || events.skipped != swiftTestingReport.skipped
            || events.cancelled.rawValue > 0
            || events.runIssues.rawValue > 0
            || events.functionNames != swiftTestingReport.cases.map(\.name).sorted() {
            return .apparatus(Diagnostic(
                code: .apparatusFailed,
                subject: "swift-testing-events",
                detail: "event lifecycle disagrees with XUnit"
            ))
        }
        let reconciliation = TestResultReconciler.reconcile(
            exitCode: execution.exitCode,
            evidence: .xunit(
                total: report.tests,
                failed: report.failures,
                errors: report.errors,
                skipped: report.skipped
            )
        )
        let complete: (Digest) -> TargetTestObservation
        switch reconciliation {
        case .passed(let count):
            complete = { .passed(count, $0) }
        case .failed(let count):
            complete = { .failed(count, $0) }
        case .apparatus(let conflict):
            return .apparatus(Diagnostic(
                code: .apparatusFailed,
                subject: "swift-package-xunit",
                detail: conflict.rawValue
            ))
        }
        var transcript = Data()
        for (library, document) in execution.resultDocuments.ordered {
            transcript.append(contentsOf: library.rawValue.utf8)
            transcript.append(58)
            transcript.append(contentsOf: String(document.count).utf8)
            transcript.append(58)
            transcript.append(document)
        }
        let inventoryBytes = Data(execution.discoveredTests.canonicalText.utf8)
        transcript.append(contentsOf: String(inventoryBytes.count).utf8)
        transcript.append(58)
        transcript.append(inventoryBytes)
        transcript.append(contentsOf: String(execution.swiftTestingEvents.bytes.count).utf8)
        transcript.append(58)
        transcript.append(execution.swiftTestingEvents.bytes)
        let digest: Digest
        do {
            digest = try .sha256(transcript)
        } catch {
            return .apparatus(Diagnostic(
                code: .apparatusFailed,
                subject: "swift-package",
                detail: "test result digest failed"
            ))
        }
        return complete(digest)
    }

    static func execute(root: String) throws(SwiftPackageTestError) -> SwiftPackageTestExecution {
        let manifest = root + "/Package.swift"
        let kind: FileEntryKind
        do {
            kind = try FileSystemBoundary.entryKind(path: manifest)
        } catch {
            throw .notPackage(root)
        }
        if kind != .file {
            throw .notPackage(root)
        }
        let scratch: ScratchDirectoryOwner
        do {
            scratch = try ScratchDirectoryOwner(
                parent: "/private/tmp",
                name: "swiftest-package-" + String(PlatformClock.monotonicNanoseconds().rawValue)
            )
        } catch let error {
            throw .platform(error)
        }
        let resultPath = scratch.path + "/tests.xml"
        let eventPath = scratch.path + "/swift-testing.jsonl"
        let sharedArguments = [
            "--package-path", root,
            "--scratch-path", scratch.path + "/build",
            "--cache-path", scratch.path + "/cache",
            "--config-path", scratch.path + "/config",
            "--security-path", scratch.path + "/security",
            "--disable-sandbox",
            "--disable-automatic-resolution",
            "--disable-index-store",
        ]
        let libraryArguments = ["--enable-xctest", "--enable-swift-testing"]
        let buildStatus: Int32
        do {
            buildStatus = try ProcessBoundary.runPinnedApple(
                executable: "/usr/bin/xcrun",
                arguments: ["swift", "build"] + sharedArguments + libraryArguments + ["--build-tests"],
                workingDirectory: root,
                scratch: scratch
            ).exitCode
        } catch let error {
            throw .platform(error)
        }
        if buildStatus != 0 {
            throw .missingResult(buildStatus)
        }
        let listing: ProcessOutput
        do {
            listing = try ProcessBoundary.runPinnedApple(
                executable: "/usr/bin/xcrun",
                arguments: ["swift", "test", "list"] + sharedArguments + libraryArguments + ["--skip-build"],
                workingDirectory: root,
                scratch: scratch
            )
        } catch let error {
            throw .platform(error)
        }
        let inventory: XUnitTestInventory
        do {
            inventory = try XUnitTestInventory.decode(listing.standardOutput)
        } catch let error {
            throw .invalidInventory(error)
        }
        let arguments = ["swift", "test"] + sharedArguments + libraryArguments + [
            "--skip-build",
            "--xunit-output=" + resultPath,
            "--event-stream-version", "6.4",
            "--event-stream-output-path=" + eventPath,
            "--parallel",
            "--num-workers", "1",
        ]
        let exitCode: Int32
        do {
            let output = try ProcessBoundary.runPinnedApple(
                executable: "/usr/bin/xcrun",
                arguments: arguments,
                workingDirectory: root,
                scratch: scratch
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
        let entries: [String]
        do {
            entries = try FileSystemBoundary.list(path: scratch.path)
        } catch {
            throw .missingResult(exitCode)
        }
        var documents: [XUnitLibrary: Data] = [:]
        for library in XUnitLibrary.allCases {
            let path: String
            switch library {
            case .xctest:
                path = resultPath
            case .swiftTesting:
                path = scratch.path + "/tests-swift-testing.xml"
            }
            let name = URL(fileURLWithPath: path).lastPathComponent
            if !entries.contains(name) {
                throw .missingResult(exitCode)
            }
            let data: Data
            do {
                data = try FileSystemBoundary.read(path: path)
            } catch let error {
                throw .platform(error)
            }
            documents[library] = data
        }
        let complete: XUnitRunnerDocuments
        do {
            complete = try XUnitRunnerDocuments(documents)
        } catch {
            throw .missingResult(exitCode)
        }
        let eventData: Data
        do {
            eventData = try FileSystemBoundary.read(path: eventPath)
        } catch let error {
            throw .platform(error)
        }
        let events: SwiftTestingCampaignEvidence
        do {
            events = try SwiftTestingCampaignEvidence.decode(eventData)
        } catch let error {
            throw .invalidStream(error)
        }
        return SwiftPackageTestExecution(
            resultDocuments: complete,
            discoveredTests: inventory,
            swiftTestingEvents: events,
            exitCode: exitCode
        )
    }
}
