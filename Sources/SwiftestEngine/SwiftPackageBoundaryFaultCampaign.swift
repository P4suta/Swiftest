import Foundation
import SwiftestCodec
import SwiftestFaults
import SwiftestModel
import SwiftestPlatform

public enum SwiftPackageBoundaryCampaignError: Error, Equatable, Sendable {
    case platform(PlatformError)
    case declaration(FaultDeclarationError)
    case evidenceEscapesScratch(String)
    case duplicateEvidencePath(String)
    case preexistingEvidence(String)
    case cleanExecutionMissing
}

public enum SwiftPackageBoundaryCampaignAuditError: Error, Equatable, Sendable {
    case fault(FaultAuditError)
    case evidenceMismatch
}

private enum RequiredEvidenceReadError: Error, Equatable, Sendable {
    case platform(PlatformError)
    case unexpectedOutcome(FaultOutcome)
}

enum SwiftPackageEvidenceReadSample: Equatable, Sendable {
    case completed(SwiftPackageEvidenceArtifact, Data)
    case denied(SwiftPackageEvidenceArtifact)

    var artifact: SwiftPackageEvidenceArtifact {
        switch self {
        case .completed(let artifact, _), .denied(let artifact):
            artifact
        }
    }
}

enum SwiftPackageEvidenceIngressError: Error, Equatable, Sendable {
    case missingRead(SwiftPackageEvidenceArtifact)
    case duplicateRead(SwiftPackageEvidenceArtifact)
    case corruptRead(SwiftPackageEvidenceArtifact)
    case multipleDenials
    case unexpectedDenial(SwiftPackageEvidenceArtifact)
    case absentDenial(SwiftPackageEvidenceArtifact)
    case wrongDenial(expected: SwiftPackageEvidenceArtifact, actual: SwiftPackageEvidenceArtifact)
}

enum SwiftPackageEvidenceIngress: Equatable, Sendable {
    case complete(SwiftPackageEvidenceBytes)
    case denied(SwiftPackageEvidenceArtifact)

    static func interpret(
        _ samples: [SwiftPackageEvidenceReadSample],
        reference: SwiftPackageEvidenceBytes
    ) throws(SwiftPackageEvidenceIngressError) -> SwiftPackageEvidenceIngress {
        var denied: SwiftPackageEvidenceArtifact?
        for artifact in SwiftPackageEvidenceArtifact.allCases {
            let matching = samples.filter { $0.artifact == artifact }
            guard let sample = matching.first else {
                throw .missingRead(artifact)
            }
            guard matching.count == 1 else {
                throw .duplicateRead(artifact)
            }
            switch sample {
            case .completed(_, let bytes):
                guard bytes == reference.bytes(for: artifact) else {
                    throw .corruptRead(artifact)
                }
            case .denied:
                guard denied == nil else {
                    throw .multipleDenials
                }
                denied = artifact
            }
        }
        if let denied {
            return .denied(denied)
        }
        return .complete(reference)
    }

    func requireClean() throws(SwiftPackageEvidenceIngressError) -> SwiftPackageEvidenceBytes {
        switch self {
        case .complete(let evidence):
            evidence
        case .denied(let artifact):
            throw .unexpectedDenial(artifact)
        }
    }

    func requireDenial(of expected: SwiftPackageEvidenceArtifact) throws(SwiftPackageEvidenceIngressError) {
        switch self {
        case .complete:
            throw .absentDenial(expected)
        case .denied(let actual):
            guard actual == expected else {
                throw .wrongDenial(expected: expected, actual: actual)
            }
        }
    }
}

public struct SwiftPackageEvidencePaths: Sendable {
    public let xctest: String
    public let swiftTesting: String
    public let eventStream: String

    public init(xctest: String, swiftTesting: String, eventStream: String) {
        self.xctest = xctest
        self.swiftTesting = swiftTesting
        self.eventStream = eventStream
    }

    fileprivate var all: [String] {
        SwiftPackageEvidenceArtifact.allCases.map(path(for:))
    }

    fileprivate func path(for artifact: SwiftPackageEvidenceArtifact) -> String {
        switch artifact {
        case .xctest: xctest
        case .swiftTesting: swiftTesting
        case .eventStream: eventStream
        }
    }
}

public struct SwiftPackageEvidenceBytes: Equatable, Sendable {
    public let xctest: Data
    public let swiftTesting: Data
    public let eventStream: Data

    public init(xctest: Data, swiftTesting: Data, eventStream: Data) {
        self.xctest = xctest
        self.swiftTesting = swiftTesting
        self.eventStream = eventStream
    }

    func bytes(for artifact: SwiftPackageEvidenceArtifact) -> Data {
        switch artifact {
        case .xctest: xctest
        case .swiftTesting: swiftTesting
        case .eventStream: eventStream
        }
    }
}

public struct SwiftPackageBoundaryCampaignRun: Sendable {
    public let exitCode: Int32
    public let evidence: SwiftPackageEvidenceBytes?
    public let observation: TargetTestObservation
    private let campaign: FaultCampaign
    private let transcript: FaultExecutionTranscript
    private let capturedEvidence: SwiftPackageEvidenceBytes?

    init(
        exitCode: Int32,
        evidence: SwiftPackageEvidenceBytes?,
        observation: TargetTestObservation,
        campaign: FaultCampaign,
        transcript: FaultExecutionTranscript,
        capturedEvidence: SwiftPackageEvidenceBytes?
    ) {
        self.exitCode = exitCode
        self.evidence = evidence
        self.observation = observation
        self.campaign = campaign
        self.transcript = transcript
        self.capturedEvidence = capturedEvidence
    }

    public func audit() throws(SwiftPackageBoundaryCampaignAuditError) -> AuditedFaultCampaign {
        let audit: AuditedFaultCampaign
        do {
            audit = try FaultAuditKernel.close(campaign: campaign, transcript: transcript)
        } catch let error {
            throw .fault(error)
        }
        guard let capturedEvidence, let evidence, evidence == capturedEvidence else {
            throw .evidenceMismatch
        }
        return audit
    }
}

public enum SwiftPackageBoundaryFaultCampaign {
    public static func run(
        executable: String,
        arguments: [String],
        workingDirectory: String,
        scratch: borrowing ScratchDirectoryOwner,
        evidencePaths: SwiftPackageEvidencePaths,
        discoveredTests: XUnitTestInventory
    ) throws(SwiftPackageBoundaryCampaignError) -> SwiftPackageBoundaryCampaignRun {
        let canonicalScratch: String
        do {
            canonicalScratch = try CanonicalPathBoundary.directory(scratch.path)
        } catch let error {
            throw .platform(error)
        }
        let prefix = canonicalScratch + "/"
        var evidenceNames = Set<String>()
        for path in evidencePaths.all {
            let parent: String
            do {
                parent = try CanonicalPathBoundary.directory(
                    URL(fileURLWithPath: path).deletingLastPathComponent().path
                )
            } catch {
                throw .evidenceEscapesScratch(path)
            }
            if parent != canonicalScratch {
                throw .evidenceEscapesScratch(path)
            }
            let destination: ExclusiveOutputOwner
            do {
                destination = try ExclusiveOutputOwner(absolutePath: path)
            } catch let error {
                switch error {
                case .outputExists:
                    throw .preexistingEvidence(path)
                default:
                    throw .platform(error)
                }
            }
            if !evidenceNames.insert(URL(fileURLWithPath: destination.path).lastPathComponent).inserted {
                throw .duplicateEvidencePath(path)
            }
        }
        let scope: SwiftPackageBoundaryScope
        do {
            scope = try StandardFaultCampaign.swiftPackageBoundaryScope()
        } catch let error {
            throw .declaration(error)
        }
        let campaign = scope.campaign
        let processPoint = scope.processLaunch
        var cleanExitCode: Int32?
        var cleanEvidence: SwiftPackageEvidenceBytes?
        var cleanObservation: TargetTestObservation?
        var capturedEvidence: SwiftPackageEvidenceBytes?
        let transcript = FaultCampaignExecutor.execute(campaign: campaign) { scenario, injector in
            switch scenario.kind {
            case .clean:
                let exitCode: Int32
                do {
                    let result = try FaultedBoundaries.processPinnedApple(
                        point: processPoint,
                        injector: &injector,
                        executable: executable,
                        arguments: arguments,
                        workingDirectory: workingDirectory,
                        scratch: scratch
                    )
                    switch result {
                    case .completed(let output):
                        exitCode = output.exitCode
                    case .injected:
                        return apparatus(scenario, "clean test process was injected")
                    }
                } catch let error as PlatformError {
                    switch error {
                    case PlatformError.processExit(_, let code, _):
                        exitCode = code
                    default:
                        return apparatus(scenario, "clean target test process did not execute")
                    }
                } catch {
                    return apparatus(scenario, "clean target test process failed outside platform boundary")
                }
                cleanExitCode = exitCode
                do {
                    let observed = try observeCleanEvidence(
                        exitCode: exitCode,
                        discoveredTests: discoveredTests,
                        scope: scope,
                        injector: &injector,
                        paths: evidencePaths,
                        scratchPrefix: prefix
                    )
                    cleanEvidence = observed.evidence
                    cleanObservation = observed.observation
                    switch observed.observation {
                    case .passed:
                        return .cleanPassed
                    case .failed:
                        return .cleanFailed(Diagnostic(
                            code: .baselineFailed,
                            subject: scenario.id.rawValue,
                            detail: "clean target test process failed"
                        ))
                    case .apparatus(let diagnostic):
                        return .apparatusFailed(diagnostic)
                    case .notConfigured:
                        return apparatus(scenario, "clean target process was not configured")
                    }
                } catch {
                    let diagnostic = Diagnostic(
                        code: .apparatusFailed,
                        subject: scenario.id.rawValue,
                        detail: "clean evidence read failed"
                    )
                    cleanObservation = .apparatus(diagnostic)
                    return .apparatusFailed(diagnostic)
                }
            case .single:
                guard let activation = scenario.activations.first,
                    scenario.activations.count == 1 else {
                    return apparatus(scenario, "single fault activation is incomplete")
                }
                let before: SwiftPackageEvidenceBytes
                let beforeEntries: [String]
                do {
                    before = try captureEvidence(evidencePaths, scratchPrefix: prefix)
                    beforeEntries = try FileSystemBoundary.list(path: scratch.path)
                    guard let cleanEvidence, before == cleanEvidence else {
                        return apparatus(scenario, "clean target result evidence changed before injection")
                    }
                } catch {
                    return apparatus(scenario, "clean target result evidence is incomplete")
                }
                let lease: FileEventLease
                do {
                    let watched = [WatchedInput(path: canonicalScratch, kind: .directory)]
                        + evidencePaths.all.map {
                            WatchedInput(
                                path: prefix + URL(fileURLWithPath: $0).lastPathComponent,
                                kind: .file
                            )
                        }
                    lease = try FileEventLease(inputs: watched)
                } catch {
                    return apparatus(scenario, "target result evidence could not be watched")
                }
                let denialReceipt: SwiftPackageDenialReceipt
                let observedOutcome: FaultOutcome
                if activation.id == processPoint {
                    do {
                        let result = try FaultedBoundaries.processPinnedApple(
                            point: processPoint,
                            injector: &injector,
                            executable: executable,
                            arguments: arguments,
                            workingDirectory: workingDirectory,
                            scratch: scratch
                        )
                        switch result {
                        case .completed:
                            return apparatus(scenario, "process-launch fault did not suppress execution")
                        case .injected(let outcome):
                            guard let receipt = SwiftPackageTargetObserver.denialReceipt(
                                .processDenied,
                                scope: scope,
                                discoveredTests: discoveredTests
                            ) else {
                                return apparatus(scenario, "process-launch denial was accepted by target observer")
                            }
                            denialReceipt = receipt
                            observedOutcome = outcome
                        }
                    } catch {
                        return apparatus(scenario, "injected process boundary failed unexpectedly")
                    }
                } else if let artifact = scope.readArtifact(for: activation.id) {
                    do {
                        let ingress = try SwiftPackageEvidenceIngress.interpret(
                            collectEvidenceReads(scope: scope, injector: &injector, paths: evidencePaths),
                            reference: before
                        )
                        try ingress.requireDenial(of: artifact)
                        guard let cleanExitCode else {
                            return apparatus(scenario, "clean target process exit is unavailable")
                        }
                        guard let receipt = SwiftPackageTargetObserver.denialReceipt(
                            .evidence(exitCode: cleanExitCode, ingress),
                            scope: scope,
                            discoveredTests: discoveredTests
                        ) else {
                            return apparatus(scenario, "evidence denial was accepted by target observer")
                        }
                        denialReceipt = receipt
                        observedOutcome = .filesystemPermissionDenied
                    } catch {
                        return apparatus(scenario, "injected evidence ingress did not fail closed")
                    }
                } else {
                    return apparatus(scenario, "undeclared Swift Package fault activation")
                }
                do {
                    try lease.requireEventFree()
                    let after = try captureEvidence(evidencePaths, scratchPrefix: prefix)
                    if after != before {
                        return apparatus(scenario, "faulted process changed target result evidence")
                    }
                    let afterEntries = try FileSystemBoundary.list(path: scratch.path)
                    if afterEntries != beforeEntries {
                        return apparatus(scenario, "faulted process changed scratch contents")
                    }
                    try lease.requireEventFree()
                    capturedEvidence = after
                } catch {
                    return apparatus(scenario, "faulted process changed target result evidence")
                }
                return denialReceipt.close(activation: activation, observedOutcome: observedOutcome)
            case .compound:
                return apparatus(scenario, "process-launch scope contains a compound fault")
            }
        }
        guard let exitCode = cleanExitCode, let observation = cleanObservation else {
            throw .cleanExecutionMissing
        }
        return SwiftPackageBoundaryCampaignRun(
            exitCode: exitCode,
            evidence: cleanEvidence,
            observation: observation,
            campaign: campaign,
            transcript: transcript,
            capturedEvidence: capturedEvidence
        )
    }

    private static func observeCleanEvidence(
        exitCode: Int32,
        discoveredTests: XUnitTestInventory,
        scope: SwiftPackageBoundaryScope,
        injector: inout FaultInjector,
        paths: SwiftPackageEvidencePaths,
        scratchPrefix: String
    ) throws -> (evidence: SwiftPackageEvidenceBytes, observation: TargetTestObservation) {
        let captured = try captureEvidence(paths, scratchPrefix: scratchPrefix)
        let ingress = try SwiftPackageEvidenceIngress.interpret(
            collectEvidenceReads(scope: scope, injector: &injector, paths: paths),
            reference: captured
        )
        let evidence = try ingress.requireClean()
        let observation = SwiftPackageTargetObserver.observe(
            .evidence(exitCode: exitCode, ingress),
            discoveredTests: discoveredTests
        )
        return (evidence, observation)
    }

    private static func apparatus(_ scenario: FaultScenario, _ detail: String) -> FaultScenarioRunResult {
        .apparatusFailed(Diagnostic(
            code: .apparatusFailed,
            subject: scenario.id.rawValue,
            detail: detail
        ))
    }

    private static func collectEvidenceReads(
        scope: SwiftPackageBoundaryScope,
        injector: inout FaultInjector,
        paths: SwiftPackageEvidencePaths
    ) throws(RequiredEvidenceReadError) -> [SwiftPackageEvidenceReadSample] {
        var samples: [SwiftPackageEvidenceReadSample] = []
        for artifact in SwiftPackageEvidenceArtifact.allCases {
            samples.append(try readRequiredEvidence(
                artifact: artifact,
                point: scope.readPoint(for: artifact),
                injector: &injector,
                path: paths.path(for: artifact)
            ))
        }
        return samples
    }

    private static func readRequiredEvidence(
        artifact: SwiftPackageEvidenceArtifact,
        point: FaultPointID,
        injector: inout FaultInjector,
        path: String
    ) throws(RequiredEvidenceReadError) -> SwiftPackageEvidenceReadSample {
        let result: FaultedReadResult
        do {
            result = try FaultedBoundaries.read(point: point, injector: &injector, path: path)
        } catch let error {
            throw .platform(error)
        }
        switch result {
        case .completed(let data):
            return .completed(artifact, data)
        case .injected(let outcome):
            if outcome == .filesystemPermissionDenied {
                return .denied(artifact)
            }
            throw .unexpectedOutcome(outcome)
        }
    }

    private static func captureEvidence(
        _ paths: SwiftPackageEvidencePaths,
        scratchPrefix: String
    ) throws(PlatformError) -> SwiftPackageEvidenceBytes {
        func read(_ path: String) throws(PlatformError) -> Data {
            let canonical = try CanonicalPathBoundary.existing(path)
            let name = URL(fileURLWithPath: path).lastPathComponent
            guard canonical == scratchPrefix + name else {
                throw .pathEscapesRoot(path)
            }
            guard try FileSystemBoundary.entryKind(path: path) == .file else {
                throw .read(path)
            }
            return try FileSystemBoundary.read(path: path)
        }
        return try SwiftPackageEvidenceBytes(
            xctest: read(paths.xctest),
            swiftTesting: read(paths.swiftTesting),
            eventStream: read(paths.eventStream)
        )
    }
}
