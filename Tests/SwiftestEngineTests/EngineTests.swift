import Foundation
@testable import SwiftestEngine
@testable import SwiftestFaults
import SwiftestModel
import SwiftestMutation
import SwiftestPlatform
import SwiftestScheduler
import SwiftestSolver
import Testing

@Test
func worldSpaceEnumeratesEveryDeclaredCombination() throws {
    let space = try worldSpace()
    let worlds = try space.allWorlds()
    #expect(try space.executionCount().rawValue == 4)
    #expect(worlds.count == 4)
    #expect(Set(worlds.map(\.build)) == [.debug, .release])
    #expect(Set(worlds.map(\.appearance)) == [.light, .dark])
}

@Test
func worldDefinitionPreimageIsTheBytesHashedIntoWorldID() throws {
    let worlds = try worldSpace().allWorlds()
    var iterator = worlds.makeIterator()
    let candidate = iterator.next()
    let first = try #require(candidate)
    let components = first.id.rawValue.split(separator: "-", omittingEmptySubsequences: false)
    guard components.count == 4 else {
        Issue.record("world ID has no definition digest")
        return
    }
    let digest = try Digest.sha256(worlds.definitionPayload)
    #expect(components[2] == digest.rawValue)
}

@Test
func worldSpaceCursorEnumeratesUnequalAxesAndMutantPairs() throws {
    struct Combination: Hashable {
        let build: BuildConfiguration
        let locale: LocaleScenario
        let appearance: Appearance
        let permission: PermissionScenario
    }

    let mutant = try MutantID.parse("mutant-1")
    let builds: [BuildConfiguration] = [.debug, .release]
    let locales: [LocaleScenario] = [.englishUnitedStates, .japaneseJapan, .arabicSaudiArabia]
    let appearances: [Appearance] = [.light, .dark]
    let permissions = [
        PermissionScenario(kind: .camera, state: .granted),
        PermissionScenario(kind: .camera, state: .denied),
    ]
    let space = try worldSpace(
        builds: builds,
        locales: locales,
        appearances: appearances,
        permissions: permissions,
        mutants: [.clean, .mutant(mutant)]
    )
    let worlds = Array(try space.allWorlds())
    #expect(worlds.count == 48)
    #expect(Set(worlds.map(\.build)) == Set(builds))
    #expect(Set(worlds.map(\.locale)).count == 3)
    let cleanWorlds = worlds.filter { $0.mutant == .clean }
    let actual = cleanWorlds.map {
        Combination(build: $0.build, locale: $0.locale, appearance: $0.appearance, permission: $0.permission)
    }
    var expected: [Combination] = []
    for build in builds {
        for locale in locales {
            for appearance in appearances {
                for permission in permissions {
                    expected.append(Combination(
                        build: build,
                        locale: locale,
                        appearance: appearance,
                        permission: permission
                    ))
                }
            }
        }
    }
    #expect(actual == expected)
    #expect(Set(actual).count == 24)
    #expect(Set(worlds.map(\.id)).count == 24)
    for pair in stride(from: 0, to: worlds.count, by: 2) {
        #expect(worlds[pair].id == worlds[pair + 1].id)
        #expect(worlds[pair].mutant == .clean)
        #expect(worlds[pair + 1].mutant == .mutant(mutant))
    }
}

@Test
func worldSpaceStreamsAnExtremelyLargeCartesianProduct() throws {
    let space = try repeatedWorldSpace(multiplicity: 4)
    let worlds = try space.allWorlds()
    #expect(worlds.count == 4_294_967_296)
    let firstFive = Array(worlds.prefix(5)).map(\.id)
    let first = try #require(firstFive.first)
    let last = try #require(firstFive.last)
    #expect(firstFive.count == 5)
    #expect(first.rawValue.hasPrefix("world-v1-"))
    #expect(Set(firstFive.prefix(4)) == [first])
    #expect(first != last)
}

@Test
func worldSpaceIteratorReachesTheLastWorldOfAnExtremelyLargeProduct() throws {
    let worlds = try repeatedWorldSpace(multiplicity: 4).allWorlds()
    var iterator = worlds.makeIterator()
    iterator.skip(try EvidenceCount.nonnegative(worlds.count - 1))
    let candidate = iterator.next()
    let last = try #require(candidate)
    #expect(last.id.rawValue.hasSuffix("-1073741823"))
    let exhausted = iterator.next()
    #expect(exhausted == nil)
    iterator.skip(try EvidenceCount.nonnegative(1))
    let stillExhausted = iterator.next()
    #expect(stillExhausted == nil)
}

@Test
func worldSpaceRejectsCartesianProductOverflow() throws {
    let space = try repeatedWorldSpace(multiplicity: 16)
    #expect(throws: WorldSpaceError.worldCountOverflow) {
        try space.executionCount()
    }
    #expect(throws: WorldSpaceError.worldCountOverflow) {
        try space.allWorlds()
    }
}

@Test
func worldIDsBindEveryNonMutantAxisAndEnumerationOrder() throws {
    let baseline = try firstWorldID(try worldSpace())
    let alternateSpaces = try [
        worldSpace(builds: [.debug, .testing]),
        worldSpace(operatingSystems: [.macOS]),
        worldSpace(deviceID: "device-2"),
        worldSpace(deviceFamily: .tablet),
        worldSpace(locales: [.japaneseJapan]),
        worldSpace(layoutDirections: [.rightToLeft]),
        worldSpace(appearances: [.light, .light]),
        worldSpace(accessibilityScenarios: [.voiceOver]),
        worldSpace(permissions: [PermissionScenario(kind: .camera, state: .denied)]),
        worldSpace(permissions: [PermissionScenario(kind: .microphone, state: .granted)]),
        worldSpace(locations: [.moving]),
        worldSpace(biometrics: [.fails]),
        worldSpace(lifecycles: [.background]),
        worldSpace(dataScenarios: [.malformed]),
        worldSpace(serviceFaults: [.timeout]),
        worldSpace(cancellations: [.duringOperation]),
        worldSpace(scheduleID: "schedule-2"),
        worldSpace(scheduleDecisions: [-1, 0, 1]),
        worldSpace(builds: [.release, .debug]),
    ]
    for space in alternateSpaces {
        #expect(try firstWorldID(space) != baseline)
    }
    #expect(Set(try alternateSpaces.map(firstWorldID)).count == alternateSpaces.count)
}

@Test
func mutantVariantsShareTheirBaseWorldID() throws {
    let mutant = try MutantID.parse("mutant-1")
    let space = try worldSpace(mutants: [.clean, .mutant(mutant)])
    let worlds = Array(try space.allWorlds().prefix(4))
    #expect(worlds[0].mutant == .clean)
    #expect(worlds[1].mutant == .mutant(mutant))
    #expect(worlds[0].id == worlds[1].id)
    #expect(worlds[0].id != worlds[2].id)
    #expect(worlds[0].id == (try firstWorldID(worldSpace(mutants: [.mutant(mutant)]))))
}

@Test
func worldIDsAreDeterministicAcrossIndependentSequences() throws {
    let space = try worldSpace()
    let first = Array(try space.allWorlds().map(\.id))
    let second = Array(try space.allWorlds().map(\.id))
    #expect(first == second)
    #expect(first.count == 4)
    for id in first {
        #expect(try WorldID.parse(id.rawValue) == id)
    }
}

@Test
func dporReductionPreservesEveryCanonicalTrace() throws {
    let resource = try ResourceID.parse("independent")
    let first = try ScheduledAction(
        id: "a",
        task: 0,
        accesses: [ResourceAccess(resource: resource, mode: .read)]
    )
    let second = try ScheduledAction(
        id: "b",
        task: 1,
        accesses: []
    )
    let full = try DeterministicScheduler.traces(tasks: [[first], [second]], proofMode: .disabled)
    let reduced = try DeterministicScheduler.traces(tasks: [[first], [second]], proofMode: .enabled)
    #expect(full.count == 2)
    #expect(reduced.count == 1)
    try DPORProofKernel.verify(full: full, reduced: reduced)
}

@Test
func satSolverCertificateIsIndependentlyChecked() throws {
    let first = try SATVariable.make(1)
    let second = try SATVariable.make(2)
    let formula = SATFormula(clauses: [
        try SATClause.make([.positive(first), .positive(second)]),
        try SATClause.make([.negative(first), .positive(second)]),
    ])
    let result = try SATSolver.solve(formula)
    switch result {
    case .satisfiable(let certificate):
        try SATProofKernel.verify(formula: formula, certificate: certificate)
    case .unsatisfiable(let certificate):
        Issue.record("unexpected unsatisfiable certificate")
        #expect(certificate.verificationDomainSize.rawValue == 0)
    }
}

@Test
func mutationLexerNeverMutatesStringsOrComments() throws {
    let source = "let text = \"true == false\"\n" + "/" + "/ true == false\nlet value = true\n"
    let candidates = try MutationEngine.discover(in: source)
    #expect(candidates.count == 1)
    #expect(candidates[0].schema == .booleanFlip)
    let mutant = try MutationEngine.apply(candidates[0], to: source)
    #expect(mutant.hasSuffix("let value = false\n"))
}

@Test
func symbolicSilDistinguishesEquivalentAndDifferentMutants() throws {
    let left = "%0 = argument 0\n%1 = integer_literal 1\n%2 = add %0 %1\nreturn %2"
    let reordered = "%0 = argument 0\n%1 = integer_literal 1\n%2 = add %1 %0\nreturn %2"
    let changed = "%0 = argument 0\n%1 = integer_literal 1\n%2 = subtract %0 %1\nreturn %2"
    #expect(try SymbolicSIL.compare(original: left, mutant: reordered) == .identical)
    #expect(try SymbolicSIL.compare(original: left, mutant: changed) == .different)
}

@Test
func standardFaultCampaignCoversEveryDomainAndDeclaredScenario() throws {
    let campaign = try StandardFaultCampaign.make()
    #expect(campaign.points.count == 26)
    #expect(campaign.compounds.count == 6)
    #expect(campaign.scenarios.count == 33)
    #expect(Set(campaign.points.map(\.domain)) == Set(FaultDomain.allCases))
    let boundary = try StandardFaultCampaign.swiftPackageBoundaryScope()
    #expect(Set(boundary.campaign.points.map(\.id)).isSubset(of: Set(campaign.points.map(\.id))))
    let transcript = standardFaultTranscript(campaign)
    let audit = try FaultAuditKernel.close(campaign: campaign, transcript: transcript)
    #expect(audit.scenarioCount.rawValue == 33)
    #expect(audit.injectedPointCount.rawValue == 38)
}

@Test
func everyUnreachedFaultInvalidatesTheCampaign() throws {
    let campaign = try StandardFaultCampaign.make()
    let passing = standardFaultTranscript(campaign).observations
    for scenario in campaign.scenarios where scenario.kind != .clean {
        guard let point = scenario.activations.first else {
            Issue.record("scenario without activation")
            continue
        }
        let failing = passing.map { observation in
            if observation.scenario != scenario.id {
                return observation
            }
            let activations = scenario.activations.map { activation in
                let result: FaultActivationResult
                if activation.id == point.id {
                    result = .unreached
                } else {
                    result = activation.expectation == .recover ? .recovered : .failedClosed
                }
                return FaultActivationObservation(point: activation.id, result: result)
            }
            return FaultScenarioObservation(scenario: scenario.id, result: .injected(activations))
        }
        do {
            let audit = try FaultAuditKernel.close(campaign: campaign, observations: failing)
            Issue.record("unreached fault accepted")
            #expect(audit.digest.rawValue.isEmpty)
        } catch let error {
            #expect(error == .faultUnreached(scenario.id, point.id))
        }
    }
}

@Test
func faultAuditRejectsMissingUndetectedAndUncontrolledResults() throws {
    let campaign = try StandardFaultCampaign.make()
    let passing = standardFaultTranscript(campaign).observations
    guard let last = passing.last else {
        Issue.record("empty fault observations")
        return
    }
    do {
        let audit = try FaultAuditKernel.close(campaign: campaign, observations: Array(passing.dropLast()))
        Issue.record("missing scenario accepted")
        #expect(audit.digest.rawValue.isEmpty)
    } catch let error {
        #expect(error == .missingScenario(last.scenario))
    }
    guard let single = campaign.scenarios.first(where: { $0.kind == .single }),
        let point = single.activations.first else {
        Issue.record("single fault scenario absent")
        return
    }
    let arbitraryDigest = try Digest.sha256(Data("unverified proof".utf8))
    for result in [FaultActivationResult.uncontrolled, .undetectedRecovered,
        .provenIrrelevant(arbitraryDigest)] {
        let replaced = passing.map { observation in
            observation.scenario == single.id
                ? FaultScenarioObservation(
                    scenario: single.id,
                    result: .injected([FaultActivationObservation(point: point.id, result: result)])
                )
                : observation
        }
        do {
            let audit = try FaultAuditKernel.close(campaign: campaign, observations: replaced)
            Issue.record("invalid fault result accepted")
            #expect(audit.digest.rawValue.isEmpty)
        } catch let error {
            switch result {
            case .uncontrolled:
                #expect(error == .faultUncontrolled(single.id, point.id))
            case .undetectedRecovered:
                #expect(error == .faultUndetected(single.id, point.id))
            case .provenIrrelevant:
                #expect(error == .unverifiedIrrelevance(single.id, point.id))
            case .recovered, .failedClosed, .unreached, .undetectedFailedClosed:
                Issue.record("unexpected result branch")
            }
        }
    }
}

@Test
func injectorReportsEveryActivationExactlyOnce() throws {
    let campaign = try StandardFaultCampaign.make()
    for scenario in campaign.scenarios {
        var injector = FaultInjector(scenario: scenario)
        for point in scenario.activations {
            let first = FaultInjectionBoundary.evaluate(
                point: point.id,
                injector: &injector,
                operation: { point.id }
            )
            if case .injected(let reached, let outcome) = first {
                #expect(reached == point.id)
                #expect(outcome == point.outcome)
            } else {
                Issue.record("declared fault did not activate")
            }
            let second = FaultInjectionBoundary.evaluate(
                point: point.id,
                injector: &injector,
                operation: { point.id }
            )
            if case .completed(let value) = second {
                #expect(value == point.id)
            } else {
                Issue.record("fault activated twice")
            }
        }
        #expect(injector.unreachedPoints().isEmpty)
    }
}

@Test
func faultBoundarySuppressesTheRealOperationAtTheInjectionPoint() throws {
    let campaign = try StandardFaultCampaign.make()
    guard let scenario = campaign.scenarios.first(where: {
        $0.activations.contains(where: { $0.id.rawValue == "clock-jump" })
    }), let point = scenario.activations.first(where: { $0.id.rawValue == "clock-jump" }) else {
        Issue.record("clock fault scenario absent")
        return
    }
    var injector = FaultInjector(scenario: scenario)
    var operationCount = 0
    let result = FaultInjectionBoundary.evaluate(
        point: point.id,
        injector: &injector,
        operation: {
            operationCount += 1
            return 7
        }
    )
    switch result {
    case .completed:
        Issue.record("faulted operation completed")
    case .injected(let injectedPoint, let outcome):
        #expect(injectedPoint == point.id)
        #expect(outcome == .clockJumped)
    }
    #expect(operationCount == 0)
}

@Test
func faultedPlatformBoundariesSuppressRealFailuresOnlyWhenInjected() throws {
    let campaign = try StandardFaultCampaign.make()
    guard let processScenario = campaign.scenarios.first(where: {
        $0.activations.contains(where: { $0.id.rawValue == "process-launch" })
    }), let readScenario = campaign.scenarios.first(where: {
        $0.activations.contains(where: { $0.id.rawValue == "filesystem-read-denied" })
    }) else {
        Issue.record("standard boundary scenarios absent")
        return
    }
    let processPoint = try FaultPointID.parse("process-launch")
    let readPoint = try FaultPointID.parse("filesystem-read-denied")
    var processInjector = FaultInjector(scenario: processScenario)
    let process = try FaultedBoundaries.process(
        point: processPoint,
        injector: &processInjector,
        executable: "/dev/null/no-such-program",
        arguments: [],
        workingDirectory: nil
    )
    if case .injected(let outcome) = process {
        #expect(outcome == .processLaunchFailure)
    } else {
        Issue.record("process launch was not injected")
    }
    var readInjector = FaultInjector(scenario: readScenario)
    let read = try FaultedBoundaries.read(
        point: readPoint,
        injector: &readInjector,
        path: "/dev/null/no-such-file"
    )
    if case .injected(let outcome) = read {
        #expect(outcome == .filesystemPermissionDenied)
    } else {
        Issue.record("filesystem read was not injected")
    }
    let clean = campaign.scenarios[0]
    var cleanInjector = FaultInjector(scenario: clean)
    #expect(throws: Error.self) {
        try FaultedBoundaries.read(
            point: readPoint,
            injector: &cleanInjector,
            path: "/dev/null/no-such-file"
        )
    }
}

@Test
func codecAndStoreFaultBoundariesUseRealOperationsInCleanControl() throws {
    let campaign = try StandardFaultCampaign.make()
    guard let codecScenario = campaign.scenarios.first(where: {
        $0.activations.contains(where: { $0.id.rawValue == "codec-duplicate-key" })
    }), let storeScenario = campaign.scenarios.first(where: {
        $0.activations.contains(where: { $0.id.rawValue == "store-checksum" })
    }) else {
        Issue.record("codec or store scenario absent")
        return
    }
    let codecPoint = try FaultPointID.parse("codec-duplicate-key")
    let storePoint = try FaultPointID.parse("store-checksum")
    let valid = Data("{\"value\":1}".utf8)
    var codecInjector = FaultInjector(scenario: codecScenario)
    let injectedDecode = try FaultedBoundaries.decode(
        point: codecPoint,
        injector: &codecInjector,
        data: valid
    )
    if case .injected(let outcome) = injectedDecode {
        #expect(outcome == .codecDuplicateKey)
    } else {
        Issue.record("codec fault was not injected")
    }
    var cleanCodec = FaultInjector(scenario: campaign.scenarios[0])
    let cleanDecode = try FaultedBoundaries.decode(
        point: codecPoint,
        injector: &cleanCodec,
        data: valid
    )
    if case .completed = cleanDecode {
        #expect(cleanCodec.unreachedPoints().isEmpty)
    } else {
        Issue.record("clean codec operation was injected")
    }
    var storeInjector = FaultInjector(scenario: storeScenario)
    let path = try ArtifactPath.parse("missing-artifact.json")
    let injectedStore = try FaultedBoundaries.storeRead(
        point: storePoint,
        injector: &storeInjector,
        root: "/dev/null",
        relativePath: path
    )
    if case .injected(let outcome) = injectedStore {
        #expect(outcome == .storeChecksumMismatch)
    } else {
        Issue.record("store fault was not injected")
    }
    var cleanStore = FaultInjector(scenario: campaign.scenarios[0])
    #expect(throws: Error.self) {
        try FaultedBoundaries.storeRead(
            point: storePoint,
            injector: &cleanStore,
            root: "/dev/null",
            relativePath: path
        )
    }
}

@Test
func faultCampaignExecutorRequiresBoundaryActivationAndObservedHandling() throws {
    let clock = try FaultPointID.parse("clock")
    let storage = try FaultPointID.parse("storage")
    let campaign = try FaultCampaign(
        points: [
            FaultPoint(
                id: clock,
                domain: .clock,
                operation: "deadline",
                outcome: .clockJumped,
                expectation: .recover
            ),
            FaultPoint(
                id: storage,
                domain: .store,
                operation: "load",
                outcome: .storeChecksumMismatch,
                expectation: .failClosed
            ),
        ],
        compounds: [CompoundFault(id: try .parse("both"), points: [clock, storage])]
    )
    var completedOperations = 0
    let observations = FaultCampaignExecutor.execute(campaign: campaign) { scenario, injector in
        var results: [FaultActivationObservation] = []
        for point in campaign.points {
            let evaluation = FaultInjectionBoundary.evaluate(
                point: point.id,
                injector: &injector,
                operation: {
                    completedOperations += 1
                    return point.id
                }
            )
            if case .injected(let activated, let outcome) = evaluation {
                #expect(activated == point.id)
                #expect(outcome == point.outcome)
                results.append(FaultActivationObservation(
                    point: point.id,
                    result: point.expectation == .recover ? .recovered : .failedClosed
                ))
            }
        }
        return scenario.kind == .clean ? .cleanPassed : .handled(results)
    }
    let audit = try FaultAuditKernel.close(campaign: campaign, transcript: observations)
    #expect(audit.scenarioCount.rawValue == 4)
    #expect(audit.injectedPointCount.rawValue == 4)
    #expect(completedOperations == 4)

    let alteredCampaign = try FaultCampaign(
        points: [
            FaultPoint(
                id: clock,
                domain: .clock,
                operation: "deadline",
                outcome: .clockJumped,
                expectation: .failClosed
            ),
            campaign.points[1],
        ],
        compounds: campaign.compounds
    )
    do {
        let mismatched = try FaultAuditKernel.close(campaign: alteredCampaign, transcript: observations)
        Issue.record("transcript accepted for a different campaign")
        #expect(mismatched.injectedPointCount.rawValue == 0)
    } catch let error {
        #expect(error == .campaignMismatch)
    }

    let untriggered = FaultCampaignExecutor.execute(campaign: campaign) { scenario, _ in
        scenario.kind == .clean ? .cleanPassed : .handled([])
    }
    #expect(untriggered.observations.contains { observation in
        if case .apparatusFailed = observation.result {
            return observation.scenario == campaign.scenarios[0].id
        }
        return false
    })
    #expect(untriggered.observations.contains { observation in
        if case .injected(let activations) = observation.result {
            return activations.contains { $0.result == .unreached }
        }
        return false
    })
    #expect(throws: FaultAuditError.self) {
        try FaultAuditKernel.close(campaign: campaign, transcript: untriggered)
    }

    let forged = FaultCampaignExecutor.execute(campaign: campaign) { scenario, _ in
        scenario.kind == .clean
            ? .cleanPassed
            : .handled(scenario.activations.map {
                FaultActivationObservation(point: $0.id, result: .recovered)
            })
    }
    #expect(forged.observations.contains { observation in
        if case .apparatusFailed = observation.result {
            return true
        }
        return false
    })
    #expect(throws: FaultAuditError.self) {
        try FaultAuditKernel.close(campaign: campaign, transcript: forged)
    }
}

@Test
func swiftTestingJSONLinesDecodesActualABIVersionAndAuditsFailures() throws {
    let stream = [
        "{\"version\":\"6.4.0\",\"kind\":\"test\",\"payload\":{\"kind\":\"function\",\"name\":\"checks()\",\"sourceLocation\":{\"filePath\":\"/tmp/Checks.swift\",\"line\":1,\"column\":1},\"id\":\"Checks/checks()\",\"isParameterized\":false}}",
        "{\"version\":\"6.4.0\",\"kind\":\"event\",\"payload\":{\"kind\":\"runStarted\",\"instant\":{\"absolute\":1,\"since1970\":2},\"messages\":[]}}",
        "{\"version\":\"6.4.0\",\"kind\":\"event\",\"payload\":{\"kind\":\"testStarted\",\"instant\":{\"absolute\":1,\"since1970\":2},\"messages\":[],\"testID\":\"Checks/checks()\"}}",
        "{\"version\":\"6.4.0\",\"kind\":\"event\",\"payload\":{\"kind\":\"issueRecorded\",\"instant\":{\"absolute\":1,\"since1970\":2},\"messages\":[{\"symbol\":\"fail\",\"text\":\"failure\"}],\"testID\":\"Checks/checks()\",\"issue\":{\"isKnown\":false,\"severity\":\"error\",\"isFailure\":true}}}",
        "{\"version\":\"6.4.0\",\"kind\":\"event\",\"payload\":{\"kind\":\"testEnded\",\"instant\":{\"absolute\":1,\"since1970\":2},\"messages\":[],\"testID\":\"Checks/checks()\"}}",
        "{\"version\":\"6.4.0\",\"kind\":\"event\",\"payload\":{\"kind\":\"runEnded\",\"instant\":{\"absolute\":1,\"since1970\":2},\"messages\":[]}}",
    ].joined(separator: "\n") + "\n"
    let records = try StableTestingABI.decodeStream(Data(stream.utf8))
    let summary = try StableTestingABI.summarize(records)
    #expect(summary.discovered.rawValue == 1)
    #expect(summary.passed.rawValue == 0)
    #expect(summary.failed.rawValue == 1)
    #expect(summary.runIssues.rawValue == 0)
    #expect(throws: SwiftTestingStreamError.self) {
        try StableTestingABI.decodeStream(Data(stream.dropLast().utf8))
    }
    let duplicateKey = "{\"version\":\"6.4.0\",\"version\":\"6.4.0\",\"kind\":\"event\",\"payload\":{}}"
    #expect(throws: SwiftTestingStreamError.self) {
        try StableTestingABI.decodeRecord(Data(duplicateKey.utf8))
    }
    let incomplete = Array(records.dropLast())
    #expect(throws: SwiftTestingStreamError.self) {
        try StableTestingABI.summarize(incomplete)
    }
}

@Test
func swiftTestingExecutableRejectsAProcessWithoutEventEvidence() throws {
    do {
        let result = try SwiftTestingExecutableDriver.run(
            executable: "/usr/bin/true",
            arguments: [],
            workingDirectory: "/private/tmp",
            scratchParent: "/private/tmp"
        )
        Issue.record("process without Swift Testing events was accepted")
        #expect(result.summary.discovered.rawValue > 0)
    } catch let error {
        if case .platform(.read(let path)) = error {
            #expect(path.hasSuffix("/testing.jsonl"))
        } else {
            Issue.record("unexpected missing-event result")
        }
    }
}

@Test
func swiftTestingExecutableConsumesAProcessEventStream() throws {
    let records = [
        "{\"version\":\"6.4.0\",\"kind\":\"test\",\"payload\":{\"kind\":\"function\",\"name\":\"passes()\",\"sourceLocation\":{\"filePath\":\"/tmp/Passes.swift\",\"line\":1,\"column\":1},\"id\":\"Passes/passes()\",\"isParameterized\":false}}",
        "{\"version\":\"6.4.0\",\"kind\":\"event\",\"payload\":{\"kind\":\"runStarted\",\"instant\":{\"absolute\":1,\"since1970\":2},\"messages\":[]}}",
        "{\"version\":\"6.4.0\",\"kind\":\"event\",\"payload\":{\"kind\":\"testStarted\",\"instant\":{\"absolute\":1,\"since1970\":2},\"messages\":[],\"testID\":\"Passes/passes()\"}}",
        "{\"version\":\"6.4.0\",\"kind\":\"event\",\"payload\":{\"kind\":\"testEnded\",\"instant\":{\"absolute\":1,\"since1970\":2},\"messages\":[],\"testID\":\"Passes/passes()\"}}",
        "{\"version\":\"6.4.0\",\"kind\":\"event\",\"payload\":{\"kind\":\"runEnded\",\"instant\":{\"absolute\":1,\"since1970\":2},\"messages\":[]}}",
    ]
    let command = "printf '%s\\n' " + records.map { "'" + $0 + "'" }.joined(separator: " ") + " > \"$1\""
    let result = try SwiftTestingExecutableDriver.run(
        executable: "/bin/sh",
        arguments: ["-c", command],
        workingDirectory: "/private/tmp",
        scratchParent: "/private/tmp"
    )
    #expect(result.exitCode == 0)
    #expect(result.summary.discovered.rawValue == 1)
    #expect(result.summary.passed.rawValue == 1)
    #expect(result.summary.failed.rawValue == 0)
}

@Test
func xcresultSummaryRejectsMalformedAndContradictoryTestEvidence() throws {
    let deviceConfiguration = """
    {"device":{"deviceId":"simulator","deviceName":"iPhone","architecture":"arm64","modelName":"iPhone","platform":"iOS Simulator","osVersion":"27.0"},"testPlanConfiguration":{"configurationId":"default","configurationName":"Default"},"passedTests":1,"failedTests":0,"skippedTests":0,"expectedFailures":0}
    """
    let valid = """
    {"title":"Tests","environmentDescription":"iOS Simulator","topInsights":[],"result":"Passed","totalTestCount":1,"passedTests":1,"failedTests":0,"skippedTests":0,"expectedFailures":0,"statistics":[],"devicesAndConfigurations":[\(deviceConfiguration)],"testFailures":[],"runtimeWarnings":[]}
    """
    let summary = try XCResultSummary.decode(Data(valid.utf8))
    #expect(summary.result == .passed)
    #expect(summary.total.rawValue == 1)
    #expect(summary.passed.rawValue == 1)
    let emptyConfigurations = valid.replacingOccurrences(
        of: "[\(deviceConfiguration)]",
        with: "[]"
    )
    #expect(throws: XCResultSummaryError.ambiguousDeviceConfigurations(0)) {
        try XCResultSummary.decode(Data(emptyConfigurations.utf8))
    }
    let multipleConfigurations = valid.replacingOccurrences(
        of: "[\(deviceConfiguration)]",
        with: "[\(deviceConfiguration),\(deviceConfiguration)]"
    )
    #expect(throws: XCResultSummaryError.ambiguousDeviceConfigurations(2)) {
        try XCResultSummary.decode(Data(multipleConfigurations.utf8))
    }
    let directObject = valid.replacingOccurrences(
        of: "[\(deviceConfiguration)]",
        with: deviceConfiguration
    )
    #expect(throws: XCResultSummaryError.codec(.expectedArray("devicesAndConfigurations"))) {
        try XCResultSummary.decode(Data(directObject.utf8))
    }
    let invalidConfiguration = valid.replacingOccurrences(
        of: "[\(deviceConfiguration)]",
        with: "[true]"
    )
    #expect(throws: XCResultSummaryError.codec(.expectedObject)) {
        try XCResultSummary.decode(Data(invalidConfiguration.utf8))
    }
    let emptyMetadata = valid.replacingOccurrences(
        of: "\"title\":\"Tests\"",
        with: "\"title\":\"\""
    )
    #expect(try XCResultSummary.decode(Data(emptyMetadata.utf8)).total.rawValue == 1)
    let inconsistent = valid.replacingOccurrences(of: "\"totalTestCount\":1", with: "\"totalTestCount\":2")
    do {
        let invalid = try XCResultSummary.decode(Data(inconsistent.utf8))
        Issue.record("inconsistent xcresult count accepted")
        #expect(invalid.total.rawValue == 0)
    } catch let error {
        #expect(error == .inconsistentTotals)
    }
    let unknown = valid.replacingOccurrences(
        of: "\"configurationName\":\"Default\"",
        with: "\"configurationName\":\"Default\",\"unexamined\":true"
    )
    do {
        let invalid = try XCResultSummary.decode(Data(unknown.utf8))
        Issue.record("unknown xcresult field accepted")
        #expect(invalid.total.rawValue == 0)
    } catch let error {
        #expect(error == .identity(.codec(.unknownField("unexamined"))))
    }
    let duplicate = valid.replacingOccurrences(
        of: "\"totalTestCount\":1",
        with: "\"totalTestCount\":1,\"totalTestCount\":1"
    )
    #expect(throws: XCResultSummaryError.self) {
        try XCResultSummary.decode(Data(duplicate.utf8))
    }
    let reversedTime = valid.replacingOccurrences(
        of: "\"title\":\"Tests\"",
        with: "\"title\":\"Tests\",\"startTime\":3,\"finishTime\":2"
    )
    do {
        let invalid = try XCResultSummary.decode(Data(reversedTime.utf8))
        Issue.record("reversed xcresult timestamps accepted")
        #expect(invalid.total.rawValue == 0)
    } catch let error {
        #expect(error == .invalidTimestamp("finishTime"))
    }
    let failedStatusWithoutFailure = valid.replacingOccurrences(
        of: "\"result\":\"Passed\"",
        with: "\"result\":\"Failed\""
    )
    do {
        let invalid = try XCResultSummary.decode(Data(failedStatusWithoutFailure.utf8))
        Issue.record("contradictory xcresult status accepted")
        #expect(invalid.total.rawValue == 0)
    } catch let error {
        #expect(error == .inconsistentStatus)
    }
}

@Test
func xcodeAppInvocationSelectsTheBuiltTestPlanAndCoverage() throws {
    let invocation = XcodeAppTestDriver.testInvocation(
        xctestrun: "/tmp/Build/Products/App.xctestrun",
        destination: "platform=iOS Simulator,name=iPhone",
        resultBundle: "/tmp/Test.xcresult",
        workingDirectory: "/tmp"
    )
    #expect(invocation.arguments == [
        "xcodebuild",
        "-xctestrun", "/tmp/Build/Products/App.xctestrun",
        "-destination", "platform=iOS Simulator,name=iPhone",
        "-resultBundlePath", "/tmp/Test.xcresult",
        "-enableCodeCoverage", "YES",
        "test-without-building",
    ])
    let fixtureDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
    do {
        let container = try XcodeContainer.discover(root: fixtureDirectory)
        Issue.record("directory without an Xcode container accepted")
        #expect(container.path.isEmpty)
    } catch let error {
        #expect(error == .invalidContainer(fixtureDirectory))
    }
    do {
        let missing = try XcodeAppTestDriver.findXctestrun(products: fixtureDirectory)
        Issue.record("missing xctestrun accepted")
        #expect(missing.isEmpty)
    } catch let error {
        #expect(error == .missingXctestrun)
    }
    let scratch = try ScratchDirectoryOwner(
        parent: "/private/tmp",
        name: "swiftest-xctestrun-version-" + String(PlatformClock.monotonicNanoseconds().rawValue)
    )
    do {
        try XcodeAppTestDriver.validateXctestrunVersion(
            path: #filePath,
            workingDirectory: fixtureDirectory,
            scratch: scratch
        )
        Issue.record("non-xctestrun source accepted as version 2")
    } catch let error {
        #expect(error == .invalidXctestrunVersion(#filePath))
    }
}

@Test
func xccovReportRejectsIncompleteAndContradictoryCoverage() throws {
    let valid = """
    {"coveredLines":1,"executableLines":2,"lineCoverage":0.5,"targets":[{"coveredLines":1,"executableLines":2,"lineCoverage":0.5,"name":"App.app","buildProductPath":"/tmp/App.app","files":[{"coveredLines":1,"executableLines":2,"lineCoverage":0.5,"name":"App.swift","path":"/tmp/App.swift","functions":[{"coveredLines":1,"executableLines":1,"lineCoverage":1,"lineNumber":3,"executionCount":1,"name":"run"}]}]}]}
    """
    let report = try XCCoverageReport.decode(Data(valid.utf8))
    #expect(report.coveredLines.rawValue == 1)
    #expect(report.executableLines.rawValue == 2)
    #expect(report.targetCount.rawValue == 1)
    let unknown = valid.replacingOccurrences(
        of: "\"name\":\"run\"",
        with: "\"name\":\"run\",\"unexamined\":true"
    )
    do {
        let invalid = try XCCoverageReport.decode(Data(unknown.utf8))
        Issue.record("unknown xccov field accepted")
        #expect(invalid.targetCount.rawValue == 0)
    } catch let error {
        #expect(error == .codec(.unknownField("unexamined")))
    }
    let impossible = valid.replacingOccurrences(
        of: "\"coveredLines\":1,\"executableLines\":2",
        with: "\"coveredLines\":3,\"executableLines\":2"
    )
    #expect(throws: XCCoverageError.self) {
        try XCCoverageReport.decode(Data(impossible.utf8))
    }
    let misleadingFraction = valid.replacingOccurrences(
        of: "\"lineCoverage\":0.5",
        with: "\"lineCoverage\":1"
    )
    do {
        let invalid = try XCCoverageReport.decode(Data(misleadingFraction.utf8))
        Issue.record("misleading xccov fraction accepted")
        #expect(invalid.coveredLines.rawValue == 0)
    } catch let error {
        #expect(error == .invalidFraction("lineCoverage"))
    }
    let duplicate = valid.replacingOccurrences(
        of: "\"coveredLines\":1,\"executableLines\":2",
        with: "\"coveredLines\":1,\"coveredLines\":1,\"executableLines\":2"
    )
    #expect(throws: XCCoverageError.self) {
        try XCCoverageReport.decode(Data(duplicate.utf8))
    }
    let empty = "{\"coveredLines\":0,\"executableLines\":0,\"lineCoverage\":0,\"targets\":[]}"
    do {
        let invalid = try XCCoverageReport.decode(Data(empty.utf8))
        Issue.record("empty xccov target set accepted")
        #expect(invalid.targetCount.rawValue > 0)
    } catch let error {
        #expect(error == .noTargets)
    }
    let noInstrumentation = "{\"coveredLines\":0,\"executableLines\":0,\"lineCoverage\":0,\"targets\":[{}]}"
    do {
        let invalid = try XCCoverageReport.decode(Data(noInstrumentation.utf8))
        Issue.record("uninstrumented xccov output accepted")
        #expect(invalid.executableLines.rawValue > 0)
    } catch let error {
        #expect(error == .noExecutableLines)
    }
}

@Test
func propertyRunnerShrinksFailuresDeterministically() throws {
    let iterations = try IterationCount.positive(64)
    let generator = try PropertyGenerator<Int>.integers(in: 1...100)
    let result = try PropertyRunner.check(
        iterations: iterations,
        seed: 7,
        generator: generator,
        shrinker: .towardZero,
        predicate: { $0 == 0 }
    )
    switch result {
    case .failed(let value, let iteration):
        #expect(value == 1)
        #expect(iteration.rawValue == 1)
    case .passed(let count):
        Issue.record("unexpected property pass")
        #expect(count.rawValue == 0)
    }
}

@Test
func propertyRunnerRejectsSelfCyclesAndIncreasingShrinks() throws {
    let iterations = try IterationCount.positive(1)
    let generator = PropertyGenerator<Int> { _ in 5 }
    for candidate in [5, 6] {
        let shrinker = PropertyShrinker<Int>(
            measure: { value in UInt64(value.magnitude) },
            candidates: { _ in [candidate] }
        )
        do {
            let result = try PropertyRunner.check(
                iterations: iterations,
                seed: 1,
                generator: generator,
                shrinker: shrinker,
                predicate: { value in value == 0 }
            )
            Issue.record("non-decreasing shrink accepted")
            if case .passed(let count) = result {
                #expect(count.rawValue == 0)
            }
        } catch let error {
            #expect(error == .nonDecreasingShrinkMeasure(
                current: 5,
                candidate: UInt64(candidate)
            ))
        }
    }
}

private func repeatedWorldSpace(multiplicity: Int) throws -> WorldSpace {
    func repeated<Value: Hashable & Sendable>(_ value: Value) -> AxisSelection<Value> {
        .enumerated(Array(repeating: value, count: multiplicity))
    }
    var iterator = try worldSpace().allWorlds().makeIterator()
    let candidate = iterator.next()
    let first = try #require(candidate)
    return WorldSpace(
        builds: repeated(first.build),
        operatingSystems: repeated(first.operatingSystem),
        devices: repeated(first.device),
        locales: repeated(first.locale),
        layoutDirections: repeated(first.layoutDirection),
        appearances: repeated(first.appearance),
        accessibilityScenarios: repeated(first.accessibility),
        permissions: repeated(first.permission),
        locations: repeated(first.location),
        biometrics: repeated(first.biometrics),
        lifecycles: repeated(first.lifecycle),
        dataScenarios: repeated(first.data),
        serviceFaults: repeated(first.serviceFault),
        cancellations: repeated(first.cancellation),
        schedules: repeated(first.schedule),
        mutants: repeated(first.mutant)
    )
}

private func firstWorldID(_ space: WorldSpace) throws -> WorldID {
    var iterator = try space.allWorlds().makeIterator()
    return try #require(iterator.next()?.id)
}

private func worldSpace(
    builds: [BuildConfiguration] = [.debug, .release],
    operatingSystems: [AppleOperatingSystem] = [.iOS],
    deviceID: String = "device-1",
    deviceFamily: DeviceFamily = .phone,
    locales: [LocaleScenario] = [.englishUnitedStates],
    layoutDirections: [LayoutDirection] = [.leftToRight],
    appearances: [Appearance] = [.light, .dark],
    accessibilityScenarios: [AccessibilityScenario] = [.standard],
    permissions: [PermissionScenario] = [PermissionScenario(kind: .camera, state: .granted)],
    locations: [LocationScenario] = [.fixed],
    biometrics: [BiometricScenario] = [.succeeds],
    lifecycles: [LifecycleScenario] = [.foreground],
    dataScenarios: [DataScenario] = [.typical],
    serviceFaults: [ServiceFault] = [.none],
    cancellations: [CancellationScenario] = [.never],
    scheduleID: String = "schedule-1",
    scheduleDecisions: [Int] = [],
    mutants: [MutantSelection] = [.clean]
) throws -> WorldSpace {
    let device = DeviceProfile(id: try DeviceID.parse(deviceID), family: deviceFamily)
    let schedule = ScheduleScenario(id: try ScheduleID.parse(scheduleID), decisions: scheduleDecisions)
    return WorldSpace(
        builds: .enumerated(builds),
        operatingSystems: .enumerated(operatingSystems),
        devices: .enumerated([device]),
        locales: .enumerated(locales),
        layoutDirections: .enumerated(layoutDirections),
        appearances: .enumerated(appearances),
        accessibilityScenarios: .enumerated(accessibilityScenarios),
        permissions: .enumerated(permissions),
        locations: .enumerated(locations),
        biometrics: .enumerated(biometrics),
        lifecycles: .enumerated(lifecycles),
        dataScenarios: .enumerated(dataScenarios),
        serviceFaults: .enumerated(serviceFaults),
        cancellations: .enumerated(cancellations),
        schedules: .enumerated([schedule]),
        mutants: .enumerated(mutants)
    )
}

private func standardFaultTranscript(_ campaign: FaultCampaign) -> FaultExecutionTranscript {
    FaultCampaignExecutor.execute(campaign: campaign) { scenario, injector in
        var observed: [FaultActivationObservation] = []
        for point in campaign.points {
            let evaluation = FaultInjectionBoundary.evaluate(
                point: point.id,
                injector: &injector,
                operation: { point.id }
            )
            if case .injected(let activated, _) = evaluation {
                observed.append(FaultActivationObservation(
                    point: activated,
                    result: point.expectation == .recover ? .recovered : .failedClosed
                ))
            }
        }
        return scenario.kind == .clean ? .cleanPassed : .handled(observed)
    }
}
