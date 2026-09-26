public enum BuildConfiguration: String, CaseIterable, Hashable, Sendable {
    case debug
    case release
    case testing
}

public enum AppleOperatingSystem: String, CaseIterable, Hashable, Sendable {
    case macOS
    case iOS
    case iPadOS
    case tvOS
    case watchOS
    case visionOS
}

public enum DeviceFamily: String, CaseIterable, Hashable, Sendable {
    case mac
    case phone
    case tablet
    case television
    case watch
    case spatial
}

public struct DeviceProfile: Hashable, Sendable {
    public let id: DeviceID
    public let family: DeviceFamily

    public init(id: DeviceID, family: DeviceFamily) {
        self.id = id
        self.family = family
    }
}

public enum LocaleScenario: String, CaseIterable, Hashable, Sendable {
    case englishUnitedStates = "en-US"
    case japaneseJapan = "ja-JP"
    case arabicSaudiArabia = "ar-SA"
    case germanGermany = "de-DE"
}

public enum LayoutDirection: String, CaseIterable, Hashable, Sendable {
    case leftToRight = "left-to-right"
    case rightToLeft = "right-to-left"
}

public enum Appearance: String, CaseIterable, Hashable, Sendable {
    case light
    case dark
}

public enum AccessibilityScenario: String, CaseIterable, Hashable, Sendable {
    case standard
    case largestText = "largest-text"
    case voiceOver = "voice-over"
    case reduceMotion = "reduce-motion"
    case increaseContrast = "increase-contrast"
}

public enum PermissionKind: String, CaseIterable, Hashable, Sendable {
    case camera
    case microphone
    case location
    case photos
    case notifications
}

public enum PermissionState: String, CaseIterable, Hashable, Sendable {
    case undetermined
    case granted
    case denied
    case restricted
}

public struct PermissionScenario: Hashable, Sendable {
    public let kind: PermissionKind
    public let state: PermissionState

    public init(kind: PermissionKind, state: PermissionState) {
        self.kind = kind
        self.state = state
    }
}

public enum LocationScenario: String, CaseIterable, Hashable, Sendable {
    case unavailable
    case fixed
    case moving
    case reducedAccuracy = "reduced-accuracy"
}

public enum BiometricScenario: String, CaseIterable, Hashable, Sendable {
    case unavailable
    case enrolled
    case succeeds
    case fails
    case lockedOut = "locked-out"
}

public enum LifecycleScenario: String, CaseIterable, Hashable, Sendable {
    case coldLaunch = "cold-launch"
    case foreground
    case background
    case suspended
    case terminated
}

public enum DataScenario: String, CaseIterable, Hashable, Sendable {
    case empty
    case minimal
    case typical
    case maximum
    case malformed
}

public enum ServiceFault: String, CaseIterable, Hashable, Sendable {
    case none
    case timeout
    case unavailable
    case malformedResponse = "malformed-response"
    case rateLimited = "rate-limited"
}

public enum CancellationScenario: String, CaseIterable, Hashable, Sendable {
    case never
    case beforeStart = "before-start"
    case duringOperation = "during-operation"
    case afterCompletion = "after-completion"
}

public struct ScheduleScenario: Hashable, Sendable {
    public let id: ScheduleID
    public let decisions: [Int]

    public init(id: ScheduleID, decisions: [Int]) {
        self.id = id
        self.decisions = decisions
    }
}

public enum MutantSelection: Hashable, Sendable {
    case clean
    case mutant(MutantID)
}

public struct World: Hashable, Sendable {
    public let id: WorldID
    public let build: BuildConfiguration
    public let operatingSystem: AppleOperatingSystem
    public let device: DeviceProfile
    public let locale: LocaleScenario
    public let layoutDirection: LayoutDirection
    public let appearance: Appearance
    public let accessibility: AccessibilityScenario
    public let permission: PermissionScenario
    public let location: LocationScenario
    public let biometrics: BiometricScenario
    public let lifecycle: LifecycleScenario
    public let data: DataScenario
    public let serviceFault: ServiceFault
    public let cancellation: CancellationScenario
    public let schedule: ScheduleScenario
    public let mutant: MutantSelection

    public init(
        id: WorldID,
        build: BuildConfiguration,
        operatingSystem: AppleOperatingSystem,
        device: DeviceProfile,
        locale: LocaleScenario,
        layoutDirection: LayoutDirection,
        appearance: Appearance,
        accessibility: AccessibilityScenario,
        permission: PermissionScenario,
        location: LocationScenario,
        biometrics: BiometricScenario,
        lifecycle: LifecycleScenario,
        data: DataScenario,
        serviceFault: ServiceFault,
        cancellation: CancellationScenario,
        schedule: ScheduleScenario,
        mutant: MutantSelection
    ) {
        self.id = id
        self.build = build
        self.operatingSystem = operatingSystem
        self.device = device
        self.locale = locale
        self.layoutDirection = layoutDirection
        self.appearance = appearance
        self.accessibility = accessibility
        self.permission = permission
        self.location = location
        self.biometrics = biometrics
        self.lifecycle = lifecycle
        self.data = data
        self.serviceFault = serviceFault
        self.cancellation = cancellation
        self.schedule = schedule
        self.mutant = mutant
    }
}

public struct NonInterferenceProof<Axis>: Hashable, Sendable {
    public let certificate: Digest

    private init(certificate: Digest) {
        self.certificate = certificate
    }
}

public enum AxisSelection<Value: Hashable & Sendable>: Hashable, Sendable {
    case enumerated([Value])
    case proven(representative: Value, proof: NonInterferenceProof<Value>)

    public var executionValues: [Value] {
        switch self {
        case .enumerated(let values):
            values
        case .proven(let representative, _):
            [representative]
        }
    }

    public var declaredValueCount: Int {
        switch self {
        case .enumerated(let values):
            values.count
        case .proven:
            1
        }
    }
}
