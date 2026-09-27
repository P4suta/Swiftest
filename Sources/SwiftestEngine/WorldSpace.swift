import Foundation
import SwiftestModel

public enum WorldSpaceError: Error, Equatable, Sendable {
    case emptyAxis(String)
    case worldCountOverflow
    case identityEncodingOverflow
    case identityDigest(DigestError)
}

fileprivate struct WorldAxisPlan {
    let definition: Digest
    let definitionPayload: Data
    let count: EvidenceCount
    let mutantCount: Int
}

public struct WorldSpace: Hashable, Sendable {
    public let builds: AxisSelection<BuildConfiguration>
    public let operatingSystems: AxisSelection<AppleOperatingSystem>
    public let devices: AxisSelection<DeviceProfile>
    public let locales: AxisSelection<LocaleScenario>
    public let layoutDirections: AxisSelection<LayoutDirection>
    public let appearances: AxisSelection<Appearance>
    public let accessibilityScenarios: AxisSelection<AccessibilityScenario>
    public let permissions: AxisSelection<PermissionScenario>
    public let locations: AxisSelection<LocationScenario>
    public let biometrics: AxisSelection<BiometricScenario>
    public let lifecycles: AxisSelection<LifecycleScenario>
    public let dataScenarios: AxisSelection<DataScenario>
    public let serviceFaults: AxisSelection<ServiceFault>
    public let cancellations: AxisSelection<CancellationScenario>
    public let schedules: AxisSelection<ScheduleScenario>
    public let mutants: AxisSelection<MutantSelection>

    public init(
        builds: AxisSelection<BuildConfiguration>,
        operatingSystems: AxisSelection<AppleOperatingSystem>,
        devices: AxisSelection<DeviceProfile>,
        locales: AxisSelection<LocaleScenario>,
        layoutDirections: AxisSelection<LayoutDirection>,
        appearances: AxisSelection<Appearance>,
        accessibilityScenarios: AxisSelection<AccessibilityScenario>,
        permissions: AxisSelection<PermissionScenario>,
        locations: AxisSelection<LocationScenario>,
        biometrics: AxisSelection<BiometricScenario>,
        lifecycles: AxisSelection<LifecycleScenario>,
        dataScenarios: AxisSelection<DataScenario>,
        serviceFaults: AxisSelection<ServiceFault>,
        cancellations: AxisSelection<CancellationScenario>,
        schedules: AxisSelection<ScheduleScenario>,
        mutants: AxisSelection<MutantSelection>
    ) {
        self.builds = builds
        self.operatingSystems = operatingSystems
        self.devices = devices
        self.locales = locales
        self.layoutDirections = layoutDirections
        self.appearances = appearances
        self.accessibilityScenarios = accessibilityScenarios
        self.permissions = permissions
        self.locations = locations
        self.biometrics = biometrics
        self.lifecycles = lifecycles
        self.dataScenarios = dataScenarios
        self.serviceFaults = serviceFaults
        self.cancellations = cancellations
        self.schedules = schedules
        self.mutants = mutants
    }

    public func executionCount() throws(WorldSpaceError) -> EvidenceCount {
        try axisPlan().count
    }

    public func allWorlds() throws(WorldSpaceError) -> WorldSequence {
        let plan = try axisPlan()
        return WorldSequence(
            space: self,
            plan: plan
        )
    }

    private func axisPlan() throws(WorldSpaceError) -> WorldAxisPlan {
        var encoder = try WorldDefinitionEncoder()
        try encoder.appendRawAxis("build", builds)
        try encoder.appendRawAxis("operating-system", operatingSystems)
        try encoder.appendAxis("device", devices) { (encoder: inout WorldDefinitionEncoder, value: DeviceProfile) throws(WorldSpaceError) in
            try encoder.appendString(value.id.rawValue)
            try encoder.appendString(value.family.rawValue)
        }
        try encoder.appendRawAxis("locale", locales)
        try encoder.appendRawAxis("layout-direction", layoutDirections)
        try encoder.appendRawAxis("appearance", appearances)
        try encoder.appendRawAxis("accessibility", accessibilityScenarios)
        try encoder.appendAxis("permission", permissions) { (encoder: inout WorldDefinitionEncoder, value: PermissionScenario) throws(WorldSpaceError) in
            try encoder.appendString(value.kind.rawValue)
            try encoder.appendString(value.state.rawValue)
        }
        try encoder.appendRawAxis("location", locations)
        try encoder.appendRawAxis("biometrics", biometrics)
        try encoder.appendRawAxis("lifecycle", lifecycles)
        try encoder.appendRawAxis("data", dataScenarios)
        try encoder.appendRawAxis("service-fault", serviceFaults)
        try encoder.appendRawAxis("cancellation", cancellations)
        try encoder.appendAxis("schedule", schedules) { (encoder: inout WorldDefinitionEncoder, value: ScheduleScenario) throws(WorldSpaceError) in
            try encoder.appendString(value.id.rawValue)
            try encoder.appendLength(value.decisions.count)
            for decision in value.decisions {
                try encoder.appendString(String(decision))
            }
        }
        let mutantCount = try encoder.appendMutants(mutants)
        return try encoder.plan(mutantCount: mutantCount)
    }
}

private struct WorldDefinitionEncoder {
    private var bytes = Data()
    private var worldCount = 1

    init() throws(WorldSpaceError) {
        try appendString("swiftest.world-definition.v1")
    }

    mutating func appendString(_ value: String) throws(WorldSpaceError) {
        let encoded = Array(value.utf8)
        try appendLength(encoded.count)
        bytes.append(contentsOf: encoded)
    }

    mutating func appendLength(_ value: Int) throws(WorldSpaceError) {
        guard let length = UInt64(exactly: value) else {
            throw .identityEncodingOverflow
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((length >> UInt64(shift)) & 0xff))
        }
    }

    mutating func appendRawAxis<Value: RawRepresentable & Hashable & Sendable>(
        _ name: String,
        _ selection: AxisSelection<Value>
    ) throws(WorldSpaceError) where Value.RawValue == String {
        try appendAxis(name, selection) { (encoder: inout WorldDefinitionEncoder, value: Value) throws(WorldSpaceError) in
            try encoder.appendString(value.rawValue)
        }
    }

    mutating func appendAxis<Value: Hashable & Sendable>(
        _ name: String,
        _ selection: AxisSelection<Value>,
        encode: (inout WorldDefinitionEncoder, Value) throws(WorldSpaceError) -> Void
    ) throws(WorldSpaceError) {
        try appendCardinality(name: name, count: selection.executionValues.count)
        try appendString(name)
        switch selection {
        case .enumerated(let values):
            bytes.append(0)
            try appendLength(values.count)
            for value in values {
                try encode(&self, value)
            }
        case .proven(let representative, let proof):
            bytes.append(1)
            try encode(&self, representative)
            try appendString(proof.certificate.rawValue)
        }
    }

    mutating func appendMutants(_ selection: AxisSelection<MutantSelection>) throws(WorldSpaceError) -> Int {
        let count = selection.executionValues.count
        try appendCardinality(name: "mutant", count: count)
        return count
    }

    private mutating func appendCardinality(name: String, count: Int) throws(WorldSpaceError) {
        if count == 0 {
            throw .emptyAxis(name)
        }
        let multiplication = worldCount.multipliedReportingOverflow(by: count)
        if multiplication.overflow {
            throw .worldCountOverflow
        }
        worldCount = multiplication.partialValue
    }

    func plan(mutantCount: Int) throws(WorldSpaceError) -> WorldAxisPlan {
        do {
            let definitionPayload = bytes
            return try WorldAxisPlan(
                definition: Digest.sha256(definitionPayload),
                definitionPayload: definitionPayload,
                count: EvidenceCount.nonnegative(worldCount),
                mutantCount: mutantCount
            )
        } catch let error as DigestError {
            throw .identityDigest(error)
        } catch {
            throw .worldCountOverflow
        }
    }
}

public struct WorldSequence: Sequence, Sendable {
    private let space: WorldSpace
    private let plan: WorldAxisPlan

    var definitionPayload: Data {
        plan.definitionPayload
    }

    public var executionCount: EvidenceCount {
        plan.count
    }

    public var count: Int {
        plan.count.rawValue
    }

    fileprivate init(space: WorldSpace, plan: WorldAxisPlan) {
        self.space = space
        self.plan = plan
    }

    public func makeIterator() -> WorldIterator {
        WorldIterator(space: space, plan: plan)
    }
}

private struct CartesianCursor {
    let ordinal: Int
    private var stride: Int

    init(total: Int, ordinal: Int) {
        self.ordinal = ordinal
        self.stride = total
    }

    mutating func take<Value: Hashable & Sendable>(_ selection: AxisSelection<Value>) -> Value {
        let values = selection.executionValues
        stride /= values.count
        return values[(ordinal / stride) % values.count]
    }
}

public struct WorldIterator: IteratorProtocol {
    private let space: WorldSpace
    private let plan: WorldAxisPlan
    private var position: Int

    fileprivate init(space: WorldSpace, plan: WorldAxisPlan) {
        self.space = space
        self.plan = plan
        self.position = 0
    }

    mutating func skip(_ distance: EvidenceCount) {
        let remaining = plan.count.rawValue - position
        if distance.rawValue >= remaining {
            position = plan.count.rawValue
        } else {
            position += distance.rawValue
        }
    }

    public mutating func next() -> World? {
        if position == plan.count.rawValue {
            return nil
        }
        var cursor = CartesianCursor(total: plan.count.rawValue, ordinal: position)
        let world = World(
            id: WorldID.baseWorld(definition: plan.definition, ordinal: UInt(position / plan.mutantCount)),
            build: cursor.take(space.builds),
            operatingSystem: cursor.take(space.operatingSystems),
            device: cursor.take(space.devices),
            locale: cursor.take(space.locales),
            layoutDirection: cursor.take(space.layoutDirections),
            appearance: cursor.take(space.appearances),
            accessibility: cursor.take(space.accessibilityScenarios),
            permission: cursor.take(space.permissions),
            location: cursor.take(space.locations),
            biometrics: cursor.take(space.biometrics),
            lifecycle: cursor.take(space.lifecycles),
            data: cursor.take(space.dataScenarios),
            serviceFault: cursor.take(space.serviceFaults),
            cancellation: cursor.take(space.cancellations),
            schedule: cursor.take(space.schedules),
            mutant: cursor.take(space.mutants)
        )
        position += 1
        return world
    }
}
