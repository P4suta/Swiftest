import Foundation
import SwiftestCodec
import SwiftestFaults
import SwiftestModel

public enum TargetTestObservation: Equatable, Sendable {
    case notConfigured
    case passed(EvidenceCount, Digest)
    case failed(EvidenceCount, Digest)
    case apparatus(Diagnostic)

    public var executionCount: EvidenceCount {
        switch self {
        case .notConfigured, .apparatus:
            return .zero
        case .passed(let count, _), .failed(let count, _):
            return count
        }
    }

    public var resultDigest: Digest? {
        switch self {
        case .passed(_, let digest), .failed(_, let digest):
            return digest
        case .notConfigured, .apparatus:
            return nil
        }
    }
}

enum SwiftPackageTargetIngress: Sendable {
    case processDenied
    case evidence(exitCode: Int32, SwiftPackageEvidenceIngress)
}

struct SwiftPackageDenialReceipt: ~Copyable {
    private let point: FaultPointID
    private let expectedOutcome: FaultOutcome

    fileprivate init(point: FaultPointID, expectedOutcome: FaultOutcome) {
        self.point = point
        self.expectedOutcome = expectedOutcome
    }

    consuming func close(
        activation: FaultPoint,
        observedOutcome: FaultOutcome
    ) -> FaultScenarioRunResult {
        guard activation.id == point,
            activation.expectation == .failClosed,
            activation.outcome == expectedOutcome,
            observedOutcome == expectedOutcome else {
            return .apparatusFailed(Diagnostic(
                code: .apparatusFailed,
                subject: activation.id.rawValue,
                detail: "observed denial disagrees with activated fault"
            ))
        }
        return .handled([FaultActivationObservation(point: point, result: .failedClosed)])
    }
}

enum SwiftPackageTargetObserver {
    static func denialReceipt(
        _ ingress: SwiftPackageTargetIngress,
        scope: SwiftPackageBoundaryScope,
        discoveredTests: XUnitTestInventory
    ) -> SwiftPackageDenialReceipt? {
        let point: FaultPointID
        let outcome: FaultOutcome
        let expected: Diagnostic
        switch ingress {
        case .processDenied:
            point = scope.processLaunch
            outcome = .processLaunchFailure
            expected = Diagnostic(
                code: .apparatusFailed,
                subject: "swift-package-process",
                detail: "test process launch was denied"
            )
        case .evidence(_, .denied(let artifact)):
            point = scope.readPoint(for: artifact)
            outcome = .filesystemPermissionDenied
            expected = Diagnostic(
                code: .apparatusFailed,
                subject: "swift-package-evidence-" + artifact.rawValue,
                detail: "required test evidence read was denied"
            )
        case .evidence(_, .complete):
            return nil
        }
        guard observe(ingress, discoveredTests: discoveredTests) == .apparatus(expected) else {
            return nil
        }
        return SwiftPackageDenialReceipt(point: point, expectedOutcome: outcome)
    }

    static func observe(
        _ ingress: SwiftPackageTargetIngress,
        discoveredTests: XUnitTestInventory
    ) -> TargetTestObservation {
        switch ingress {
        case .processDenied:
            return .apparatus(Diagnostic(
                code: .apparatusFailed,
                subject: "swift-package-process",
                detail: "test process launch was denied"
            ))
        case .evidence(_, .denied(let artifact)):
            return .apparatus(Diagnostic(
                code: .apparatusFailed,
                subject: "swift-package-evidence-" + artifact.rawValue,
                detail: "required test evidence read was denied"
            ))
        case .evidence(let exitCode, .complete(let evidence)):
            return observeComplete(
                evidence: evidence,
                discoveredTests: discoveredTests,
                exitCode: exitCode
            )
        }
    }

    private static func observeComplete(
        evidence: SwiftPackageEvidenceBytes,
        discoveredTests: XUnitTestInventory,
        exitCode: Int32
    ) -> TargetTestObservation {
        let documents: XUnitRunnerDocuments
        do {
            documents = try XUnitRunnerDocuments([
                .xctest: evidence.xctest,
                .swiftTesting: evidence.swiftTesting,
            ])
        } catch {
            return .apparatus(Diagnostic(
                code: .invalidWire,
                subject: "swift-package-xunit",
                detail: "incomplete test result documents"
            ))
        }
        let swiftTestingEvents: SwiftTestingCampaignEvidence
        do {
            swiftTestingEvents = try SwiftTestingCampaignEvidence.decode(evidence.eventStream)
        } catch {
            return .apparatus(Diagnostic(
                code: .invalidWire,
                subject: "swift-testing-events",
                detail: "incomplete or malformed test lifecycle"
            ))
        }
        let report: XUnitReport
        do {
            report = try XUnitCodec.decodeRunnerDocuments(documents)
        } catch {
            return .apparatus(Diagnostic(
                code: .invalidWire,
                subject: "swift-package-xunit",
                detail: "malformed test result"
            ))
        }
        let xctestReport: XUnitReport
        do {
            xctestReport = try XUnitCodec.decode(documents.xctest)
        } catch {
            return .apparatus(Diagnostic(
                code: .invalidWire,
                subject: "xctest-xunit",
                detail: "malformed XCTest result"
            ))
        }
        let swiftTestingReport: XUnitReport
        do {
            swiftTestingReport = try XUnitCodec.decode(documents.swiftTesting)
        } catch {
            return .apparatus(Diagnostic(
                code: .invalidWire,
                subject: "swift-testing-xunit",
                detail: "malformed Swift Testing result"
            ))
        }
        do {
            try discoveredTests.verify(xctest: xctestReport, swiftTesting: swiftTestingReport)
        } catch {
            return .apparatus(Diagnostic(
                code: .apparatusFailed,
                subject: "swift-package-inventory",
                detail: "discovered and executed tests disagree"
            ))
        }
        let events = swiftTestingEvents.summary
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
            exitCode: exitCode,
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
        var transcript = EvidenceTranscript()
        transcript.append("swift-package-v1")
        for (library, document) in documents.ordered {
            transcript.append(library.rawValue)
            transcript.append(document)
        }
        transcript.append("discovered-tests")
        transcript.append(discoveredTests.canonicalText)
        transcript.append("swift-testing-events")
        transcript.append(swiftTestingEvents.bytes)
        let digest: Digest
        do {
            digest = try transcript.digest()
        } catch {
            return .apparatus(Diagnostic(
                code: .apparatusFailed,
                subject: "swift-package",
                detail: "test result digest failed"
            ))
        }
        return complete(digest)
    }
}
