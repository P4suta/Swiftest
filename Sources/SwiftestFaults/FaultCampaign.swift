import Foundation
import SwiftestModel

public struct FaultPointID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    private init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func parse(_ value: String) throws(IdentifierError) -> FaultPointID {
        let checked = try RunID.parse(value)
        return FaultPointID(rawValue: checked.rawValue)
    }

    static func standard(_ value: String) -> FaultPointID {
        FaultPointID(rawValue: value)
    }

    public var description: String { rawValue }
}

public struct CompoundFaultID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    private init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func parse(_ value: String) throws(IdentifierError) -> CompoundFaultID {
        let checked = try RunID.parse(value)
        return CompoundFaultID(rawValue: checked.rawValue)
    }

    static func standard(_ value: String) -> CompoundFaultID {
        CompoundFaultID(rawValue: value)
    }

    public var description: String { rawValue }
}

public struct FaultScenarioID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    private init(rawValue: String) {
        self.rawValue = rawValue
    }

    static func clean() -> FaultScenarioID {
        FaultScenarioID(rawValue: "fault-clean")
    }

    static func single(_ point: FaultPointID) -> FaultScenarioID {
        FaultScenarioID(rawValue: "fault-single-" + point.rawValue)
    }

    static func compound(_ compound: CompoundFaultID) -> FaultScenarioID {
        FaultScenarioID(rawValue: "fault-compound-" + compound.rawValue)
    }

    public var description: String { rawValue }
}

public enum FaultDomain: String, CaseIterable, Sendable {
    case process
    case filesystem
    case codec
    case store
    case network
    case clock
    case randomness
    case device
    case cancellation
    case scheduler
    case testRunner = "test-runner"
}

public enum FaultOutcome: Hashable, Sendable {
    case processLaunchFailure
    case processExit(Int32)
    case filesystemPermissionDenied
    case filesystemCapacityExhausted
    case filesystemPartialWrite
    case codecCorruption
    case codecDuplicateKey
    case storeChecksumMismatch
    case networkDisconnected
    case networkTimedOut
    case clockJumped
    case randomnessRepeated
    case deviceRevoked
    case cancellationRequested
    case schedulerPreempted
    case testRunnerCrashed
}

public enum FaultExpectation: String, Sendable {
    case recover
    case failClosed = "fail-closed"
}

public struct FaultPoint: Hashable, Sendable {
    public let id: FaultPointID
    public let domain: FaultDomain
    public let operation: String
    public let outcome: FaultOutcome
    public let expectation: FaultExpectation

    public init(
        id: FaultPointID,
        domain: FaultDomain,
        operation: String,
        outcome: FaultOutcome,
        expectation: FaultExpectation
    ) {
        self.id = id
        self.domain = domain
        self.operation = operation
        self.outcome = outcome
        self.expectation = expectation
    }
}

public struct CompoundFault: Hashable, Sendable {
    public let id: CompoundFaultID
    public let points: [FaultPointID]

    public init(id: CompoundFaultID, points: [FaultPointID]) {
        self.id = id
        self.points = points
    }
}

public enum FaultScenarioKind: String, Sendable {
    case clean
    case single
    case compound
}

public struct FaultScenario: Hashable, Sendable {
    public let id: FaultScenarioID
    public let kind: FaultScenarioKind
    public let activations: [FaultPoint]

    init(id: FaultScenarioID, kind: FaultScenarioKind, activations: [FaultPoint]) {
        self.id = id
        self.kind = kind
        self.activations = activations
    }
}

public enum FaultDeclarationError: Error, Equatable, Sendable {
    case emptyPoints
    case duplicatePoint(FaultPointID)
    case duplicateCompound(CompoundFaultID)
    case emptyCompound(CompoundFaultID)
    case duplicateCompoundPoint(CompoundFaultID, FaultPointID)
    case unknownPoint(CompoundFaultID, FaultPointID)
}

public struct FaultCampaign: Sendable {
    public let points: [FaultPoint]
    public let compounds: [CompoundFault]
    public let scenarios: [FaultScenario]

    public init(
        points: [FaultPoint],
        compounds: [CompoundFault]
    ) throws(FaultDeclarationError) {
        if points.isEmpty {
            throw .emptyPoints
        }
        var pointByID: [FaultPointID: FaultPoint] = [:]
        for point in points {
            if pointByID.updateValue(point, forKey: point.id) != nil {
                throw .duplicatePoint(point.id)
            }
        }
        var compoundIDs = Set<CompoundFaultID>()
        for compound in compounds {
            if !compoundIDs.insert(compound.id).inserted {
                throw .duplicateCompound(compound.id)
            }
            if compound.points.isEmpty {
                throw .emptyCompound(compound.id)
            }
            var members = Set<FaultPointID>()
            for point in compound.points {
                if !members.insert(point).inserted {
                    throw .duplicateCompoundPoint(compound.id, point)
                }
                if pointByID[point] == nil {
                    throw .unknownPoint(compound.id, point)
                }
            }
        }
        var generated: [FaultScenario] = [
            FaultScenario(id: .clean(), kind: .clean, activations: [])
        ]
        for point in points {
            generated.append(FaultScenario(id: .single(point.id), kind: .single, activations: [point]))
        }
        for compound in compounds {
            var activations: [FaultPoint] = []
            for pointID in compound.points {
                guard let point = pointByID[pointID] else {
                    throw .unknownPoint(compound.id, pointID)
                }
                activations.append(point)
            }
            generated.append(FaultScenario(
                id: .compound(compound.id),
                kind: .compound,
                activations: activations
            ))
        }
        self.points = points
        self.compounds = compounds
        self.scenarios = generated
    }
}

public enum FaultActivationResult: Hashable, Sendable {
    case recovered
    case failedClosed
    case unreached
    case uncontrolled
    case undetectedRecovered
    case undetectedFailedClosed
    case provenIrrelevant(Digest)
}

public struct FaultActivationObservation: Hashable, Sendable {
    public let point: FaultPointID
    public let result: FaultActivationResult

    public init(point: FaultPointID, result: FaultActivationResult) {
        self.point = point
        self.result = result
    }
}

public enum FaultExecutionResult: Hashable, Sendable {
    case cleanPassed
    case cleanFailed(Diagnostic)
    case injected([FaultActivationObservation])
    case apparatusFailed(Diagnostic)
}

public struct FaultScenarioObservation: Hashable, Sendable {
    public let scenario: FaultScenarioID
    public let result: FaultExecutionResult

    public init(scenario: FaultScenarioID, result: FaultExecutionResult) {
        self.scenario = scenario
        self.result = result
    }
}

public enum FaultAuditError: Error, Equatable, Sendable {
    case duplicateScenario(FaultScenarioID)
    case unknownScenario(FaultScenarioID)
    case missingScenario(FaultScenarioID)
    case invalidCleanResult(FaultScenarioID)
    case cleanFailed(Diagnostic)
    case apparatusFailed(FaultScenarioID, Diagnostic)
    case duplicateActivation(FaultScenarioID, FaultPointID)
    case unknownActivation(FaultScenarioID, FaultPointID)
    case missingActivation(FaultScenarioID, FaultPointID)
    case faultUnreached(FaultScenarioID, FaultPointID)
    case faultUncontrolled(FaultScenarioID, FaultPointID)
    case faultUndetected(FaultScenarioID, FaultPointID)
    case unexpectedRecovery(FaultScenarioID, FaultPointID)
    case unexpectedFailClosed(FaultScenarioID, FaultPointID)
    case digest(DigestError)
    case count(NumericValueError)
}

public struct AuditedFaultCampaign: Sendable {
    public let digest: Digest
    public let scenarioCount: EvidenceCount
    public let injectedPointCount: EvidenceCount

    init(digest: Digest, scenarioCount: EvidenceCount, injectedPointCount: EvidenceCount) {
        self.digest = digest
        self.scenarioCount = scenarioCount
        self.injectedPointCount = injectedPointCount
    }
}

public enum FaultAuditKernel {
    public static func close(
        campaign: FaultCampaign,
        observations: [FaultScenarioObservation]
    ) throws(FaultAuditError) -> AuditedFaultCampaign {
        var scenarioByID: [FaultScenarioID: FaultScenario] = [:]
        for scenario in campaign.scenarios {
            scenarioByID[scenario.id] = scenario
        }
        var observationByID: [FaultScenarioID: FaultScenarioObservation] = [:]
        for observation in observations {
            guard scenarioByID[observation.scenario] != nil else {
                throw .unknownScenario(observation.scenario)
            }
            if observationByID.updateValue(observation, forKey: observation.scenario) != nil {
                throw .duplicateScenario(observation.scenario)
            }
        }
        var injectedPointCount = 0
        var transcript: [String] = []
        for scenario in campaign.scenarios {
            guard let observation = observationByID[scenario.id] else {
                throw .missingScenario(scenario.id)
            }
            transcript.append(scenario.id.rawValue)
            switch observation.result {
            case .cleanPassed:
                if scenario.kind != .clean {
                    throw .invalidCleanResult(scenario.id)
                }
            case .cleanFailed(let diagnostic):
                throw .cleanFailed(diagnostic)
            case .apparatusFailed(let diagnostic):
                throw .apparatusFailed(scenario.id, diagnostic)
            case .injected(let activations):
                if scenario.kind == .clean {
                    throw .invalidCleanResult(scenario.id)
                }
                var expected: [FaultPointID: FaultPoint] = [:]
                for point in scenario.activations {
                    expected[point.id] = point
                }
                var observed = Set<FaultPointID>()
                for activation in activations {
                    guard let point = expected[activation.point] else {
                        throw .unknownActivation(scenario.id, activation.point)
                    }
                    if !observed.insert(activation.point).inserted {
                        throw .duplicateActivation(scenario.id, activation.point)
                    }
                    try validate(activation.result, point: point, scenario: scenario.id)
                    transcript.append(activation.point.rawValue + ":" + resultCode(activation.result))
                    let increment = injectedPointCount.addingReportingOverflow(1)
                    if increment.overflow {
                        throw .count(.overflow)
                    }
                    injectedPointCount = increment.partialValue
                }
                for point in scenario.activations where !observed.contains(point.id) {
                    throw .missingActivation(scenario.id, point.id)
                }
            }
        }
        let digest: Digest
        do {
            digest = try .sha256(Data(transcript.joined(separator: "\n").utf8))
        } catch let error {
            throw .digest(error)
        }
        let scenarioCount: EvidenceCount
        let pointCount: EvidenceCount
        do {
            scenarioCount = try .nonnegative(campaign.scenarios.count)
            pointCount = try .nonnegative(injectedPointCount)
        } catch let error {
            throw .count(error)
        }
        return AuditedFaultCampaign(
            digest: digest,
            scenarioCount: scenarioCount,
            injectedPointCount: pointCount
        )
    }

    static func validate(
        _ result: FaultActivationResult,
        point: FaultPoint,
        scenario: FaultScenarioID
    ) throws(FaultAuditError) {
        switch result {
        case .recovered:
            if point.expectation != .recover {
                throw .unexpectedRecovery(scenario, point.id)
            }
        case .failedClosed:
            if point.expectation != .failClosed {
                throw .unexpectedFailClosed(scenario, point.id)
            }
        case .unreached:
            throw .faultUnreached(scenario, point.id)
        case .uncontrolled:
            throw .faultUncontrolled(scenario, point.id)
        case .undetectedRecovered, .undetectedFailedClosed:
            throw .faultUndetected(scenario, point.id)
        case .provenIrrelevant:
            break
        }
    }

    static func resultCode(_ result: FaultActivationResult) -> String {
        switch result {
        case .recovered:
            "recovered"
        case .failedClosed:
            "failed-closed"
        case .unreached:
            "unreached"
        case .uncontrolled:
            "uncontrolled"
        case .undetectedRecovered:
            "undetected-recovered"
        case .undetectedFailedClosed:
            "undetected-failed-closed"
        case .provenIrrelevant(let digest):
            "proven-irrelevant:" + digest.rawValue
        }
    }
}

public struct FaultInjector: ~Copyable {
    private let scenario: FaultScenario
    private var fired: Set<FaultPointID>

    public init(scenario: FaultScenario) {
        self.scenario = scenario
        self.fired = []
    }

    public mutating func outcome(at point: FaultPointID) -> FaultOutcome? {
        if fired.contains(point) {
            return nil
        }
        guard let activation = scenario.activations.first(where: { $0.id == point }) else {
            return nil
        }
        fired.insert(point)
        return activation.outcome
    }

    public borrowing func unreachedPoints() -> [FaultPointID] {
        scenario.activations.compactMap { point in
            fired.contains(point.id) ? nil : point.id
        }
    }
}
