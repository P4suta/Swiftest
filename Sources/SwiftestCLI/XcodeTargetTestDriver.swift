import Foundation
import Swiftest
import SwiftestPlatform

enum XcodeTargetTestDriver {
    static func observe(
        root: String,
        scheme: String,
        destination: String,
        project: String?,
        workspace: String?
    ) -> TargetTestObservation {
        let container: XcodeContainer
        do {
            if let project {
                guard let path = resolved(path: project, root: root) else {
                    return apparatus("xcode-container", "project escapes repository")
                }
                container = try .project(path)
            } else if let workspace {
                guard let path = resolved(path: workspace, root: root) else {
                    return apparatus("xcode-container", "workspace escapes repository")
                }
                container = try .workspace(path)
            } else {
                container = try .discover(root: root)
            }
        } catch {
            return apparatus("xcode-container", "project or workspace unavailable")
        }
        let scratchParent: String
        if let configured = EnvironmentBoundary.value(for: "TMPDIR") {
            scratchParent = configured
        } else {
            scratchParent = "/private/tmp"
        }
        let result: XcodeAppTestResult
        do {
            result = try XcodeAppTestDriver.run(
                container: container,
                scheme: scheme,
                destination: destination,
                workingDirectory: root,
                scratchParent: scratchParent
            )
        } catch {
            return apparatus("xcode-runner", "build, test, result, or coverage evidence incomplete")
        }
        let reconciliation = TestResultReconciler.reconcile(
            exitCode: result.exitCode,
            evidence: .xcresult(
                status: result.summary.result,
                total: result.summary.total,
                passed: result.summary.passed,
                failed: result.summary.failed,
                skipped: result.summary.skipped,
                expectedFailures: result.summary.expectedFailures,
                failureRecords: result.summary.failureRecords
            )
        )
        let complete: (Digest) -> TargetTestObservation
        switch reconciliation {
        case .passed(let count):
            complete = { .passed(count, $0) }
        case .failed(let count):
            complete = { .failed(count, $0) }
        case .apparatus(let conflict):
            return apparatus("xcresult", conflict.rawValue)
        }
        let digest: Digest
        do {
            digest = try .sha256(Data((
                result.summaryDigest.rawValue + ":" + result.coverageDigest.rawValue
            ).utf8))
        } catch {
            return apparatus("xcresult", "result digest failed")
        }
        return complete(digest)
    }

    static func unconfiguredProject(root: String) -> TargetTestObservation {
        do {
            let container = try XcodeContainer.discover(root: root)
            return apparatus(container.path, "scheme and destination are required")
        } catch let error {
            switch error {
            case .invalidContainer:
                return .notConfigured
            default:
                return apparatus("xcode-container", "project or workspace discovery failed")
            }
        }
    }

    private static func resolved(path: String, root: String) -> String? {
        let repository = URL(fileURLWithPath: root).standardizedFileURL
        let candidate: URL
        if path.hasPrefix("/") {
            candidate = URL(fileURLWithPath: path).standardizedFileURL
        } else {
            candidate = repository.appendingPathComponent(path).standardizedFileURL
        }
        let prefix = repository.path.hasSuffix("/") ? repository.path : repository.path + "/"
        if !candidate.path.hasPrefix(prefix) {
            return nil
        }
        return candidate.path
    }

    private static func apparatus(_ subject: String, _ detail: String) -> TargetTestObservation {
        .apparatus(Diagnostic(code: .apparatusFailed, subject: subject, detail: detail))
    }
}
