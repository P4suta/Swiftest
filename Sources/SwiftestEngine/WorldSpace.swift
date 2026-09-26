import SwiftestModel

public enum WorldSpaceError: Error, Equatable, Sendable {
    case emptyAxis(String)
    case worldCountOverflow
    case worldIdentifier(IdentifierError)
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
        let counts = executionCounts()
        try ensureNonempty(counts)
        var product = 1
        for count in counts {
            let multiplication = product.multipliedReportingOverflow(by: count)
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

    public func allWorlds() throws(WorldSpaceError) -> [World] {
        let buildValues = builds.executionValues
        let operatingSystemValues = operatingSystems.executionValues
        let deviceValues = devices.executionValues
        let localeValues = locales.executionValues
        let layoutDirectionValues = layoutDirections.executionValues
        let appearanceValues = appearances.executionValues
        let accessibilityValues = accessibilityScenarios.executionValues
        let permissionValues = permissions.executionValues
        let locationValues = locations.executionValues
        let biometricValues = biometrics.executionValues
        let lifecycleValues = lifecycles.executionValues
        let dataValues = dataScenarios.executionValues
        let serviceFaultValues = serviceFaults.executionValues
        let cancellationValues = cancellations.executionValues
        let scheduleValues = schedules.executionValues
        let mutantValues = mutants.executionValues
        let counts = executionCounts()
        try ensureNonempty(counts)
        let count = try executionCount().rawValue
        var result: [World] = []
        result.reserveCapacity(count)
        var indices = Array(repeating: 0, count: counts.count)
        var finished = false
        while !finished {
            let id: WorldID
            do {
                id = try WorldID.parse("world-" + String(result.count))
            } catch let error {
                throw .worldIdentifier(error)
            }
            result.append(World(
                id: id,
                build: buildValues[indices[0]],
                operatingSystem: operatingSystemValues[indices[1]],
                device: deviceValues[indices[2]],
                locale: localeValues[indices[3]],
                layoutDirection: layoutDirectionValues[indices[4]],
                appearance: appearanceValues[indices[5]],
                accessibility: accessibilityValues[indices[6]],
                permission: permissionValues[indices[7]],
                location: locationValues[indices[8]],
                biometrics: biometricValues[indices[9]],
                lifecycle: lifecycleValues[indices[10]],
                data: dataValues[indices[11]],
                serviceFault: serviceFaultValues[indices[12]],
                cancellation: cancellationValues[indices[13]],
                schedule: scheduleValues[indices[14]],
                mutant: mutantValues[indices[15]]
            ))
            finished = increment(&indices, counts: counts)
        }
        return result
    }

    private func executionCounts() -> [Int] {
        [
            builds.executionValues.count,
            operatingSystems.executionValues.count,
            devices.executionValues.count,
            locales.executionValues.count,
            layoutDirections.executionValues.count,
            appearances.executionValues.count,
            accessibilityScenarios.executionValues.count,
            permissions.executionValues.count,
            locations.executionValues.count,
            biometrics.executionValues.count,
            lifecycles.executionValues.count,
            dataScenarios.executionValues.count,
            serviceFaults.executionValues.count,
            cancellations.executionValues.count,
            schedules.executionValues.count,
            mutants.executionValues.count,
        ]
    }

    private func ensureNonempty(_ counts: [Int]) throws(WorldSpaceError) {
        let names = [
            "build",
            "operating-system",
            "device",
            "locale",
            "layout-direction",
            "appearance",
            "accessibility",
            "permission",
            "location",
            "biometrics",
            "lifecycle",
            "data",
            "service-fault",
            "cancellation",
            "schedule",
            "mutant",
        ]
        for index in counts.indices where counts[index] == 0 {
            throw .emptyAxis(names[index])
        }
    }

    private func increment(_ indices: inout [Int], counts: [Int]) -> Bool {
        for axis in indices.indices.reversed() {
            indices[axis] += 1
            if indices[axis] < counts[axis] {
                return false
            }
            indices[axis] = 0
        }
        return true
    }
}
