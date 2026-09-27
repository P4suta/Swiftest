import Foundation
@testable import SwiftestEngine
import SwiftestCodec
import SwiftestFaults
import SwiftestModel
import SwiftestPlatform
import Testing

@Test
func swiftPackageFaultCampaignSuppressesLaunchAndEveryEvidenceRead() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-process-campaign-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let paths = SwiftPackageEvidencePaths(
        xctest: scratch.path + "/xctest.txt",
        swiftTesting: scratch.path + "/swift-testing.txt",
        eventStream: scratch.path + "/events.txt"
    )
    let evidence = campaignEvidence(outcome: .passed)
    let invocations = scratch.path + "/invocations.txt"
    let run = try SwiftPackageBoundaryFaultCampaign.run(
        executable: "/bin/sh",
        arguments: [
            "-c", campaignWriteCommand(evidence: evidence) + "; printf run >> \"$4\"",
            "sh", paths.xctest, paths.swiftTesting, paths.eventStream, invocations,
        ],
        workingDirectory: "/private/tmp",
        scratch: scratch,
        evidencePaths: paths,
        discoveredTests: try campaignInventory()
    )
    #expect(run.exitCode == 0)
    #expect(try FileSystemBoundary.read(path: invocations) == Data("run".utf8))
    #expect(run.evidence == evidence)
    guard case .passed(let count, _) = run.observation else {
        Issue.record("clean target evidence did not pass production observation")
        return
    }
    #expect(count.rawValue == 1)
    let audit = try run.audit()
    let scope = try StandardFaultCampaign.swiftPackageBoundaryScope()
    #expect(audit.scenarioCount.rawValue == 5)
    #expect(audit.injectedPointCount.rawValue == 4)
    #expect(audit.pointIDs == [scope.processLaunch]
        + SwiftPackageEvidenceArtifact.allCases.map { scope.readPoint(for: $0) })
}

@Test
func swiftPackageFaultCampaignRejectsFailedCleanControlWithoutEvidence() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-process-failed-control-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let run = try SwiftPackageBoundaryFaultCampaign.run(
        executable: "/bin/sh",
        arguments: ["-c", "exit 7"],
        workingDirectory: "/private/tmp",
        scratch: scratch,
        evidencePaths: SwiftPackageEvidencePaths(
            xctest: scratch.path + "/missing-xctest.txt",
            swiftTesting: scratch.path + "/missing-swift-testing.txt",
            eventStream: scratch.path + "/missing-events.txt"
        ),
        discoveredTests: try campaignInventory()
    )
    #expect(run.exitCode == 7)
    guard case .apparatus = run.observation else {
        Issue.record("missing failed-control evidence was not classified as apparatus failure")
        return
    }
    do {
        let audit = try run.audit()
        Issue.record("failed clean control produced an audit")
        #expect(audit.injectedPointCount.rawValue == 0)
    } catch let error {
        if case .fault(.apparatusFailed) = error {
            #expect(true)
        } else {
            Issue.record("missing failed-control evidence yielded a different audit error")
        }
    }
}

@Test
func swiftPackageFaultCampaignRejectsFailedCleanControlWithCompleteEvidence() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-process-failed-evidence-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let paths = SwiftPackageEvidencePaths(
        xctest: scratch.path + "/xctest.txt",
        swiftTesting: scratch.path + "/swift-testing.txt",
        eventStream: scratch.path + "/events.txt"
    )
    let evidence = campaignEvidence(outcome: .failed)
    let run = try SwiftPackageBoundaryFaultCampaign.run(
        executable: "/bin/sh",
        arguments: [
            "-c", campaignWriteCommand(evidence: evidence) + "; exit 7",
            "sh", paths.xctest, paths.swiftTesting, paths.eventStream,
        ],
        workingDirectory: "/private/tmp",
        scratch: scratch,
        evidencePaths: paths,
        discoveredTests: try campaignInventory()
    )
    #expect(run.exitCode == 7)
    #expect(run.evidence == evidence)
    guard case .failed(let count, _) = run.observation else {
        Issue.record("complete failed-control evidence was not classified as a test failure")
        return
    }
    #expect(count.rawValue == 1)
    do {
        let audit = try run.audit()
        Issue.record("failed clean control produced a fault audit")
        #expect(audit.injectedPointCount.rawValue == 0)
    } catch let error {
        if case .fault(.cleanFailed) = error {
            #expect(true)
        } else {
            Issue.record("complete failed-control evidence yielded a different audit error")
        }
    }
}

@Test
func swiftPackageFaultCampaignRejectsMissingEvidenceAfterCleanRun() throws {
    for missing in SwiftPackageEvidenceArtifact.allCases {
        let scratch = try ScratchDirectoryOwner(
            parent: "/private/tmp",
            name: "swiftest-process-missing-evidence-" + String(PlatformClock.monotonicNanoseconds().rawValue)
        )
        let paths = SwiftPackageEvidencePaths(
            xctest: scratch.path + "/xctest.txt",
            swiftTesting: scratch.path + "/swift-testing.txt",
            eventStream: scratch.path + "/events.txt"
        )
        let commands: [(SwiftPackageEvidenceArtifact, String)] = [
            (.xctest, "printf x > \"$1\""),
            (.swiftTesting, "printf y > \"$2\""),
            (.eventStream, "printf z > \"$3\""),
        ]
        let script = commands.filter { $0.0 != missing }.map(\.1).joined(separator: "; ")
        let run = try SwiftPackageBoundaryFaultCampaign.run(
            executable: "/bin/sh",
            arguments: ["-c", script, "sh", paths.xctest, paths.swiftTesting, paths.eventStream],
            workingDirectory: "/private/tmp",
            scratch: scratch,
            evidencePaths: paths,
            discoveredTests: try campaignInventory()
        )
        #expect(run.exitCode == 0)
        #expect(run.evidence == nil)
        do {
            let audit = try run.audit()
            Issue.record("missing target evidence produced a fault audit")
            #expect(audit.injectedPointCount.rawValue == 0)
        } catch let error {
            if case .fault(.apparatusFailed) = error {
                #expect(true)
            } else {
                Issue.record("missing target evidence yielded a different audit error")
            }
        }
    }
}

@Test
func swiftPackageFaultCampaignRejectsAliasedEvidencePaths() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-process-aliased-evidence-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let path = scratch.path + "/shared.txt"
    let inventory = try campaignInventory()
    do {
        let run = try SwiftPackageBoundaryFaultCampaign.run(
            executable: "/usr/bin/true",
            arguments: [],
            workingDirectory: "/private/tmp",
            scratch: scratch,
            evidencePaths: SwiftPackageEvidencePaths(
                xctest: path,
                swiftTesting: path,
                eventStream: scratch.path + "/events.txt"
            ),
            discoveredTests: inventory
        )
        Issue.record("aliased evidence paths were accepted")
        #expect(run.exitCode != 0)
    } catch let error {
        #expect(error == .duplicateEvidencePath(path))
    }
}

@Test
func swiftPackageFaultCampaignRejectsEvidenceOutsideOwnedScratch() throws {
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-process-escaped-evidence-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    let inventory = try campaignInventory()
    do {
        let run = try SwiftPackageBoundaryFaultCampaign.run(
            executable: "/usr/bin/true",
            arguments: [],
            workingDirectory: "/private/tmp",
            scratch: scratch,
            evidencePaths: SwiftPackageEvidencePaths(
                xctest: "/private/tmp/outside-evidence.txt",
                swiftTesting: scratch.path + "/swift-testing.txt",
                eventStream: scratch.path + "/events.txt"
            ),
            discoveredTests: inventory
        )
        Issue.record("escaped evidence path was accepted")
        #expect(run.exitCode != 0)
    } catch let error {
        #expect(error == .evidenceEscapesScratch("/private/tmp/outside-evidence.txt"))
    }
}

@Test
func swiftPackageFaultCampaignRejectsPreexistingResultsFromNoOpProcess() throws {
    for name in ["xctest.txt", "swift-testing.txt", "events.txt"] {
        let scratch = try ScratchDirectoryOwner(
            parent: "/private/tmp",
            name: "swiftest-process-preexisting-results-" + String(PlatformClock.monotonicNanoseconds().rawValue)
        )
        let paths = SwiftPackageEvidencePaths(
            xctest: scratch.path + "/xctest.txt",
            swiftTesting: scratch.path + "/swift-testing.txt",
            eventStream: scratch.path + "/events.txt"
        )
        try FileSystemBoundary.write(
            Data(name.utf8),
            relativePath: ArtifactPath.parse(name),
            capability: scratch.issueWriteCapability()
        )
        #expect(throws: SwiftPackageBoundaryCampaignError.preexistingEvidence(scratch.path + "/" + name)) {
            try SwiftPackageBoundaryFaultCampaign.run(
                executable: "/usr/bin/true",
                arguments: [],
                workingDirectory: "/private/tmp",
                scratch: scratch,
                evidencePaths: paths,
                discoveredTests: try campaignInventory()
            )
        }
    }
}

@Test
func swiftPackageFaultCampaignRejectsPreexistingEvidenceLinksAndDirectories() throws {
    for kind in [FileEntryKind.symbolicLink, .directory] {
        let scratch = try ScratchDirectoryOwner(
            parent: "/private/tmp",
            name: "swiftest-process-preexisting-entry-" + String(PlatformClock.monotonicNanoseconds().rawValue)
        )
        let paths = SwiftPackageEvidencePaths(
            xctest: scratch.path + "/xctest.txt",
            swiftTesting: scratch.path + "/swift-testing.txt",
            eventStream: scratch.path + "/events.txt"
        )
        let existing = try ArtifactPath.parse("xctest.txt")
        switch kind {
        case .symbolicLink:
            try FileSystemBoundary.createSymbolicLink(
                relativePath: existing,
                destination: ArtifactPath.parse("missing.txt"),
                capability: scratch.issueWriteCapability()
            )
        case .directory:
            try FileSystemBoundary.createDirectory(
                relativePath: existing,
                capability: scratch.issueWriteCapability()
            )
        case .file, .other:
            Issue.record("unexpected preexisting evidence entry kind")
        }
        #expect(throws: SwiftPackageBoundaryCampaignError.preexistingEvidence(paths.xctest)) {
            try SwiftPackageBoundaryFaultCampaign.run(
                executable: "/usr/bin/true",
                arguments: [],
                workingDirectory: "/private/tmp",
                scratch: scratch,
                evidencePaths: paths,
                discoveredTests: try campaignInventory()
            )
        }
    }
}

@Test
func swiftPackageEvidenceIngressRequiresEveryArtifactExactlyOnce() throws {
    let reference = SwiftPackageEvidenceBytes(
        xctest: Data("xctest".utf8),
        swiftTesting: Data("swift-testing".utf8),
        eventStream: Data("events".utf8)
    )
    let complete = evidenceSamples(for: reference)
    let ingress = try SwiftPackageEvidenceIngress.interpret(complete, reference: reference)
    #expect(try ingress.requireClean() == reference)
    for artifact in SwiftPackageEvidenceArtifact.allCases {
        let missing = complete.filter { $0.artifact != artifact }
        #expect(throws: SwiftPackageEvidenceIngressError.missingRead(artifact)) {
            try SwiftPackageEvidenceIngress.interpret(missing, reference: reference)
        }
        let duplicate = complete + [.completed(artifact, reference.bytes(for: artifact))]
        #expect(throws: SwiftPackageEvidenceIngressError.duplicateRead(artifact)) {
            try SwiftPackageEvidenceIngress.interpret(duplicate, reference: reference)
        }
        let corrupted = complete.map { sample in
            sample.artifact == artifact ? .completed(artifact, Data("corrupt".utf8)) : sample
        }
        #expect(throws: SwiftPackageEvidenceIngressError.corruptRead(artifact)) {
            try SwiftPackageEvidenceIngress.interpret(corrupted, reference: reference)
        }
    }
}

@Test
func swiftPackageEvidenceIngressRejectsWrongDenialAndCrossedArtifactBytes() throws {
    let reference = SwiftPackageEvidenceBytes(
        xctest: Data("xctest".utf8),
        swiftTesting: Data("swift-testing".utf8),
        eventStream: Data("events".utf8)
    )
    let complete = evidenceSamples(for: reference)
    for artifact in SwiftPackageEvidenceArtifact.allCases {
        let injected = complete.map { sample in
            sample.artifact == artifact ? .denied(artifact) : sample
        }
        let ingress = try SwiftPackageEvidenceIngress.interpret(injected, reference: reference)
        try ingress.requireDenial(of: artifact)
        #expect(throws: SwiftPackageEvidenceIngressError.unexpectedDenial(artifact)) {
            try ingress.requireClean()
        }
        for wrong in SwiftPackageEvidenceArtifact.allCases where wrong != artifact {
            #expect(throws: SwiftPackageEvidenceIngressError.wrongDenial(expected: wrong, actual: artifact)) {
                try ingress.requireDenial(of: wrong)
            }
        }
    }
    #expect(throws: SwiftPackageEvidenceIngressError.absentDenial(.xctest)) {
        let ingress = try SwiftPackageEvidenceIngress.interpret(complete, reference: reference)
        try ingress.requireDenial(of: .xctest)
    }
    let crossed: [SwiftPackageEvidenceReadSample] = [
        .completed(.xctest, reference.swiftTesting),
        .completed(.swiftTesting, reference.xctest),
        .completed(.eventStream, reference.eventStream),
    ]
    #expect(throws: SwiftPackageEvidenceIngressError.corruptRead(.xctest)) {
        try SwiftPackageEvidenceIngress.interpret(crossed, reference: reference)
    }
    let twiceDenied: [SwiftPackageEvidenceReadSample] = [
        .denied(.xctest),
        .denied(.swiftTesting),
        .completed(.eventStream, reference.eventStream),
    ]
    #expect(throws: SwiftPackageEvidenceIngressError.multipleDenials) {
        try SwiftPackageEvidenceIngress.interpret(twiceDenied, reference: reference)
    }
}

@Test
func swiftPackageTargetObserverRejectsEveryInjectedDenialAsApparatus() throws {
    let inventory = try campaignInventory()
    let evidence = campaignEvidence(outcome: .passed)
    let clean = SwiftPackageTargetObserver.observe(
        .evidence(exitCode: 0, .complete(evidence)),
        discoveredTests: inventory
    )
    guard case .passed(let count, _) = clean else {
        Issue.record("valid clean evidence was not accepted")
        return
    }
    #expect(count.rawValue == 1)
    let processDenied = SwiftPackageTargetObserver.observe(.processDenied, discoveredTests: inventory)
    #expect(processDenied == .apparatus(Diagnostic(
        code: .apparatusFailed,
        subject: "swift-package-process",
        detail: "test process launch was denied"
    )))
    for artifact in SwiftPackageEvidenceArtifact.allCases {
        let denied = SwiftPackageTargetObserver.observe(
            .evidence(exitCode: 0, .denied(artifact)),
            discoveredTests: inventory
        )
        #expect(denied == .apparatus(Diagnostic(
            code: .apparatusFailed,
            subject: "swift-package-evidence-" + artifact.rawValue,
            detail: "required test evidence read was denied"
        )))
        #expect(denied != clean)
        #expect(denied.resultDigest == nil)
    }
}

@Test
func swiftPackageDenialReceiptBindsObservedBoundaryAndOutcome() throws {
    let scope = try StandardFaultCampaign.swiftPackageBoundaryScope()
    let inventory = try campaignInventory()
    let probes: [(SwiftPackageTargetIngress, FaultPointID, FaultOutcome)] = [
        (.processDenied, scope.processLaunch, .processLaunchFailure),
    ] + SwiftPackageEvidenceArtifact.allCases.map { artifact in
        (.evidence(exitCode: 0, .denied(artifact)), scope.readPoint(for: artifact), .filesystemPermissionDenied)
    }
    for (ingress, point, outcome) in probes {
        guard let activation = scope.campaign.points.first(where: { $0.id == point }),
            let receipt = SwiftPackageTargetObserver.denialReceipt(
                ingress,
                scope: scope,
                discoveredTests: inventory
            ) else {
            Issue.record("observed Swift Package denial did not issue a receipt")
            return
        }
        guard case .handled(let observations) = receipt.close(
            activation: activation,
            observedOutcome: outcome
        ) else {
            Issue.record("observed denial was not closed")
            return
        }
        #expect(observations == [FaultActivationObservation(point: point, result: .failedClosed)])
    }
    if case .some = SwiftPackageTargetObserver.denialReceipt(
        .evidence(exitCode: 0, .complete(campaignEvidence(outcome: .passed))),
        scope: scope,
        discoveredTests: inventory
    ) {
        Issue.record("complete evidence issued a denial receipt")
    }
    guard let other = scope.campaign.points.first(where: { $0.id == scope.readPoint(for: .xctest) }),
        let receipt = SwiftPackageTargetObserver.denialReceipt(
            .processDenied,
            scope: scope,
            discoveredTests: inventory
        ) else {
        Issue.record("fault scope did not contain a second point")
        return
    }
    guard case .apparatusFailed = receipt.close(
        activation: other,
        observedOutcome: .processLaunchFailure
    ) else {
        Issue.record("receipt was accepted for a different fault point")
        return
    }
}

private func evidenceSamples(for reference: SwiftPackageEvidenceBytes) -> [SwiftPackageEvidenceReadSample] {
    SwiftPackageEvidenceArtifact.allCases.map { artifact in
        .completed(artifact, reference.bytes(for: artifact))
    }
}

private func campaignInventory() throws -> XUnitTestInventory {
    try XUnitTestInventory.decode("Module.LegacyTests/testOne\n")
}

private enum CampaignFixtureOutcome {
    case passed
    case failed
}

private func campaignEvidence(outcome: CampaignFixtureOutcome) -> SwiftPackageEvidenceBytes {
    let caseResult: String
    let failureCount: String
    switch outcome {
    case .passed:
        caseResult = "<testcase classname=\"Module.LegacyTests\" name=\"testOne\"/>"
        failureCount = "0"
    case .failed:
        caseResult = "<testcase classname=\"Module.LegacyTests\" name=\"testOne\"><failure message=\"injected fixture failure\"/></testcase>"
        failureCount = "1"
    }
    let xctest = "<testsuites><testsuite name=\"TestResults\" tests=\"1\" failures=\"" + failureCount
        + "\" errors=\"0\" skipped=\"0\">" + caseResult + "</testsuite></testsuites>"
    let swiftTesting = "<testsuites><testsuite name=\"TestResults\" tests=\"0\" failures=\"0\" errors=\"0\" skipped=\"0\"/></testsuites>"
    let eventStream = [
        "{\"version\":\"6.4.0\",\"kind\":\"event\",\"payload\":{\"kind\":\"runStarted\",\"instant\":{\"absolute\":1,\"since1970\":2},\"messages\":[]}}",
        "{\"version\":\"6.4.0\",\"kind\":\"event\",\"payload\":{\"kind\":\"runEnded\",\"instant\":{\"absolute\":1,\"since1970\":2},\"messages\":[]}}",
    ].joined(separator: "\n") + "\n"
    return SwiftPackageEvidenceBytes(
        xctest: Data(xctest.utf8),
        swiftTesting: Data(swiftTesting.utf8),
        eventStream: Data(eventStream.utf8)
    )
}

private func campaignWriteCommand(evidence: SwiftPackageEvidenceBytes) -> String {
    zip(["1", "2", "3"], [evidence.xctest, evidence.swiftTesting, evidence.eventStream])
        .map { position, bytes in
            "printf '%s' '" + String(decoding: bytes, as: UTF8.self) + "' > \"$" + position + "\""
        }
        .joined(separator: "; ")
}
