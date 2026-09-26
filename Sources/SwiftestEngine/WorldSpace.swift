import SwiftestModel

public enum WorldSpaceError: Error, Equatable, Sendable {
    case emptyAxis(String)
    case worldCountOverflow
}

fileprivate struct AxisCardinality {
    let name: String
    let count: Int
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
        let cardinalities = axisCardinalities()
        var product = 1
        for axis in cardinalities {
            if axis.count == 0 {
                throw .emptyAxis(axis.name)
            }
            let multiplication = product.multipliedReportingOverflow(by: axis.count)
            if multiplication.overflow {
                throw .worldCountOverflow
            }
            product = multiplication.partialValue
        }
        do {
            return try EvidenceCount.nonnegative(product)
        } catch {
            throw .worldCountOverflow
        }
    }

    public func allWorlds() throws(WorldSpaceError) -> WorldSequence {
        let count = try executionCount().rawValue
        return WorldSequence(space: self, count: count)
    }

    fileprivate func axisCardinalities() -> [AxisCardinality] {
        [
            AxisCardinality(name: "build", count: builds.executionValues.count),
            AxisCardinality(name: "operating-system", count: operatingSystems.executionValues.count),
            AxisCardinality(name: "device", count: devices.executionValues.count),
            AxisCardinality(name: "locale", count: locales.executionValues.count),
            AxisCardinality(name: "layout-direction", count: layoutDirections.executionValues.count),
            AxisCardinality(name: "appearance", count: appearances.executionValues.count),
            AxisCardinality(name: "accessibility", count: accessibilityScenarios.executionValues.count),
            AxisCardinality(name: "permission", count: permissions.executionValues.count),
            AxisCardinality(name: "location", count: locations.executionValues.count),
            AxisCardinality(name: "biometrics", count: biometrics.executionValues.count),
            AxisCardinality(name: "lifecycle", count: lifecycles.executionValues.count),
            AxisCardinality(name: "data", count: dataScenarios.executionValues.count),
            AxisCardinality(name: "service-fault", count: serviceFaults.executionValues.count),
            AxisCardinality(name: "cancellation", count: cancellations.executionValues.count),
            AxisCardinality(name: "schedule", count: schedules.executionValues.count),
            AxisCardinality(name: "mutant", count: mutants.executionValues.count),
        ]
    }
}

public struct WorldSequence: Sequence, Sendable {
    public let count: Int
    private let space: WorldSpace

    fileprivate init(space: WorldSpace, count: Int) {
        self.space = space
        self.count = count
    }

    public func makeIterator() -> WorldIterator {
        WorldIterator(space: space, count: count)
    }
}

public struct WorldIterator: IteratorProtocol {
    private let space: WorldSpace
    private let counts: [Int]
    private var indices: [Int]
    private let count: Int
    private var position: Int

    fileprivate init(space: WorldSpace, count: Int) {
        self.space = space
        self.counts = space.axisCardinalities().map(\.count)
        self.indices = Array(repeating: 0, count: counts.count)
        self.count = count
        self.position = 0
    }

    public mutating func next() -> World? {
        if position == count {
            return nil
        }
        let world = World(
            id: WorldID.ordinal(UInt(position)),
            build: space.builds.executionValues[indices[0]],
            operatingSystem: space.operatingSystems.executionValues[indices[1]],
            device: space.devices.executionValues[indices[2]],
            locale: space.locales.executionValues[indices[3]],
            layoutDirection: space.layoutDirections.executionValues[indices[4]],
            appearance: space.appearances.executionValues[indices[5]],
            accessibility: space.accessibilityScenarios.executionValues[indices[6]],
            permission: space.permissions.executionValues[indices[7]],
            location: space.locations.executionValues[indices[8]],
            biometrics: space.biometrics.executionValues[indices[9]],
            lifecycle: space.lifecycles.executionValues[indices[10]],
            data: space.dataScenarios.executionValues[indices[11]],
            serviceFault: space.serviceFaults.executionValues[indices[12]],
            cancellation: space.cancellations.executionValues[indices[13]],
            schedule: space.schedules.executionValues[indices[14]],
            mutant: space.mutants.executionValues[indices[15]]
        )
        position += 1
        if position < count {
            advance()
        }
        return world
    }

    private mutating func advance() {
        for axis in indices.indices.reversed() {
            indices[axis] += 1
            if indices[axis] < counts[axis] {
                return
            }
            indices[axis] = 0
        }
    }
}
