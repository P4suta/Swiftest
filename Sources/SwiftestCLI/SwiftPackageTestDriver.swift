import Foundation
import Swiftest
import SwiftestCodec
import SwiftestPlatform

enum SwiftPackageTestError: Error {
    case notPackage(String)
    case platform(PlatformError)
    case missingResult(Int32)
}

struct SwiftPackageTestExecution {
    let resultDocuments: [Data]
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
            }
        }
        let report: XUnitReport
        do {
            report = try XUnitCodec.decodeDocuments(execution.resultDocuments)
        } catch {
            return .apparatus(Diagnostic(
                code: .invalidWire,
                subject: "swift-package-xunit",
                detail: "malformed test result"
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
        for document in execution.resultDocuments {
            transcript.append(contentsOf: String(document.count).utf8)
            transcript.append(58)
            transcript.append(document)
        }
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
        let scratchParent: String
        if let configured = EnvironmentBoundary.value(for: "TMPDIR") {
            scratchParent = configured
        } else {
            scratchParent = "/private/tmp"
        }
        let scratch: ScratchDirectoryOwner
        do {
            scratch = try ScratchDirectoryOwner(
                parent: scratchParent,
                name: "swiftest-package-" + String(PlatformClock.monotonicNanoseconds().rawValue)
            )
        } catch let error {
            throw .platform(error)
        }
        let resultPath = scratch.path + "/tests.xml"
        let swiftTestingPath = scratch.path + "/tests-swift-testing.xml"
        let arguments = [
            "swift", "test",
            "--package-path", root,
            "--scratch-path", scratch.path + "/build",
            "--xunit-output=" + resultPath,
            "--parallel",
            "--num-workers", "1",
            "--disable-sandbox",
            "--disable-automatic-resolution",
            "--disable-index-store",
        ]
        let exitCode: Int32
        do {
            let output = try ProcessBoundary.run(
                executable: "/usr/bin/xcrun",
                arguments: arguments,
                workingDirectory: root
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
        var documents: [Data] = []
        for path in [resultPath, swiftTestingPath] {
            let name = URL(fileURLWithPath: path).lastPathComponent
            if entries.contains(name) {
                let data: Data
                do {
                    data = try FileSystemBoundary.read(path: path)
                } catch let error {
                    throw .platform(error)
                }
                documents.append(data)
            }
        }
        if documents.isEmpty {
            throw .missingResult(exitCode)
        }
        return SwiftPackageTestExecution(resultDocuments: documents, exitCode: exitCode)
    }
}
