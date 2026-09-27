import SwiftestModel

public struct SwiftPackageBoundaryScope: Sendable {
    public let campaign: FaultCampaign
    public let processLaunch: FaultPointID

    init(campaign: FaultCampaign, processLaunch: FaultPointID) {
        self.campaign = campaign
        self.processLaunch = processLaunch
    }

    public func readPoint(for artifact: SwiftPackageEvidenceArtifact) -> FaultPointID {
        artifact.faultPoint.id
    }

    public func readArtifact(for point: FaultPointID) -> SwiftPackageEvidenceArtifact? {
        SwiftPackageEvidenceArtifact.allCases.first { readPoint(for: $0) == point }
    }
}

public enum SwiftPackageEvidenceArtifact: String, CaseIterable, Sendable {
    case xctest
    case swiftTesting = "swift-testing"
    case eventStream = "event-stream"

    fileprivate var faultPoint: FaultPoint {
        switch self {
        case .xctest:
            StandardFaultCampaign.point(
                "swift-package-xctest-read-denied", .filesystem, "xctest-read",
                .filesystemPermissionDenied, .failClosed
            )
        case .swiftTesting:
            StandardFaultCampaign.point(
                "swift-package-swift-testing-read-denied", .filesystem, "swift-testing-read",
                .filesystemPermissionDenied, .failClosed
            )
        case .eventStream:
            StandardFaultCampaign.point(
                "swift-package-event-stream-read-denied", .filesystem, "event-stream-read",
                .filesystemPermissionDenied, .failClosed
            )
        }
    }
}

public enum StandardFaultCampaign {
    public static func swiftPackageBoundaryScope() throws(FaultDeclarationError) -> SwiftPackageBoundaryScope {
        let process = swiftPackageTestLaunchPoint()
        return SwiftPackageBoundaryScope(
            campaign: try FaultCampaign(
                points: [process] + SwiftPackageEvidenceArtifact.allCases.map(\.faultPoint),
                compounds: []
            ),
            processLaunch: process.id
        )
    }

    public static func make() throws(FaultDeclarationError) -> FaultCampaign {
        let swiftPackagePoints = try swiftPackageBoundaryScope().campaign.points
        let points = [
            processLaunchPoint(),
            point("process-exit", .process, "wait", .processExit(70), .failClosed),
            filesystemReadDeniedPoint(),
            point("filesystem-write-denied", .filesystem, "write", .filesystemPermissionDenied, .failClosed),
            point("filesystem-capacity", .filesystem, "write", .filesystemCapacityExhausted, .failClosed),
            point("filesystem-partial-write", .filesystem, "commit", .filesystemPartialWrite, .recover),
            point("codec-corruption", .codec, "decode", .codecCorruption, .failClosed),
            point("codec-duplicate-key", .codec, "decode", .codecDuplicateKey, .failClosed),
            point("store-checksum", .store, "load", .storeChecksumMismatch, .failClosed),
            point("store-torn-commit", .store, "commit", .filesystemPartialWrite, .recover),
            point("network-disconnected", .network, "request", .networkDisconnected, .recover),
            point("network-timeout", .network, "request", .networkTimedOut, .recover),
            point("network-malformed", .network, "response", .codecCorruption, .failClosed),
            point("clock-jump", .clock, "deadline", .clockJumped, .recover),
            point("randomness-repeat", .randomness, "draw", .randomnessRepeated, .recover),
            point("device-revoked", .device, "lease", .deviceRevoked, .failClosed),
            point("cancellation-before-commit", .cancellation, "commit", .cancellationRequested, .recover),
            point("cancellation-during-wait", .cancellation, "wait", .cancellationRequested, .recover),
            point("scheduler-preemption", .scheduler, "yield", .schedulerPreempted, .recover),
            point("scheduler-priority-inversion", .scheduler, "lock", .schedulerPreempted, .recover),
            point("test-runner-crash", .testRunner, "execute", .testRunnerCrashed, .failClosed),
            point("test-runner-timeout", .testRunner, "execute", .networkTimedOut, .failClosed),
        ] + swiftPackagePoints
        let compounds = [
            compound("partial-write-cancellation", ["filesystem-partial-write", "cancellation-before-commit"]),
            compound("timeout-clock-jump", ["network-timeout", "clock-jump"]),
            compound("revoked-runner-crash", ["device-revoked", "test-runner-crash"]),
            compound("corruption-checksum", ["codec-corruption", "store-checksum"]),
            compound("preemption-cancellation", ["scheduler-preemption", "cancellation-during-wait"]),
            compound("process-exit-torn-commit", ["process-exit", "store-torn-commit"]),
        ]
        return try FaultCampaign(points: points, compounds: compounds)
    }

    private static func processLaunchPoint() -> FaultPoint {
        point("process-launch", .process, "launch", .processLaunchFailure, .failClosed)
    }

    private static func swiftPackageTestLaunchPoint() -> FaultPoint {
        point("swift-package-test-process-launch", .process, "test-executable-launch", .processLaunchFailure, .failClosed)
    }

    private static func filesystemReadDeniedPoint() -> FaultPoint {
        point("filesystem-read-denied", .filesystem, "read", .filesystemPermissionDenied, .failClosed)
    }

    static func point(
        _ id: String,
        _ domain: FaultDomain,
        _ operation: String,
        _ outcome: FaultOutcome,
        _ expectation: FaultExpectation
    ) -> FaultPoint {
        FaultPoint(
            id: .standard(id),
            domain: domain,
            operation: operation,
            outcome: outcome,
            expectation: expectation
        )
    }

    static func compound(_ id: String, _ points: [String]) -> CompoundFault {
        CompoundFault(
            id: .standard(id),
            points: points.map(FaultPointID.standard)
        )
    }
}
