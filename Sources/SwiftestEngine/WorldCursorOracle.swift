import Foundation
import SwiftestModel

public enum WorldCursorOracleError: Error, Equatable, Sendable {
    public enum Coordinate: String, CaseIterable, Sendable {
        case build
        case locale
        case appearance
        case permission
        case mutant
    }

    case identifier(IdentifierError)
    case digest(DigestError)
    case space(WorldSpaceError)
    case unexpectedCardinality
    case missingCoordinate(Coordinate)
    case worldID(WorldID)
    case definitionDigestMismatch(WorldID)
}

public enum WorldCursorOracle {
    private struct ParsedWorldID {
        let definition: Digest
        let baseOrdinal: UInt
    }

    private static let expectedCount = 48

    public static func text() throws(WorldCursorOracleError) -> String {
        let mutantID: MutantID
        let deviceID: DeviceID
        let scheduleID: ScheduleID
        do {
            mutantID = try MutantID.parse("oracle-mutant")
            deviceID = try DeviceID.parse("oracle-device")
            scheduleID = try ScheduleID.parse("oracle-schedule")
        } catch let error {
            throw .identifier(error)
        }
        let builds: [BuildConfiguration] = [.debug, .release]
        let locales: [LocaleScenario] = [.englishUnitedStates, .japaneseJapan, .arabicSaudiArabia]
        let appearances: [Appearance] = [.light, .dark]
        let permissions = [
            PermissionScenario(kind: .camera, state: .granted),
            PermissionScenario(kind: .camera, state: .denied),
        ]
        let mutants: [MutantSelection] = [.clean, .mutant(mutantID)]
        let space = fixture(
            deviceID: deviceID,
            scheduleID: scheduleID,
            builds: builds,
            locales: locales,
            appearances: appearances,
            permissions: permissions,
            mutants: mutants
        )
        let worlds = try sequence(in: space)
        guard worlds.count == expectedCount else {
            throw .unexpectedCardinality
        }
        let expectedDefinition = try digest(worlds.definitionPayload)
        var lines: [String] = []
        lines.reserveCapacity(worlds.count + 4)
        lines.append("world-cursor-count\t" + String(worlds.count))
        for (ordinal, world) in worlds.enumerated() {
            let identity = try parsed(world.id)
            guard identity.definition == expectedDefinition else {
                throw .definitionDigestMismatch(world.id)
            }
            let coordinates = [
                try index(world.build, in: builds, axis: .build),
                try index(world.locale, in: locales, axis: .locale),
                try index(world.appearance, in: appearances, axis: .appearance),
                try index(world.permission, in: permissions, axis: .permission),
                try index(world.mutant, in: mutants, axis: .mutant),
            ]
            lines.append(([
                "world-cursor", String(ordinal),
            ] + coordinates.map(String.init) + [String(identity.baseOrdinal)]).joined(separator: "\t"))
        }
        guard lines.count == expectedCount + 1 else {
            throw .unexpectedCardinality
        }
        let changedLocales: [LocaleScenario] = [.germanGermany, .japaneseJapan, .arabicSaudiArabia]
        let localeVariant = try sequence(in: fixture(
            deviceID: deviceID,
            scheduleID: scheduleID,
            builds: builds,
            locales: changedLocales,
            appearances: appearances,
            permissions: permissions,
            mutants: mutants
        ))
        let mutantVariant = try sequence(in: fixture(
            deviceID: deviceID,
            scheduleID: scheduleID,
            builds: builds,
            locales: locales,
            appearances: appearances,
            permissions: permissions,
            mutants: Array(mutants.reversed())
        ))
        lines.append(try preimageLine("baseline", worlds: worlds))
        lines.append(try preimageLine("locale-value", worlds: localeVariant))
        lines.append(try preimageLine("mutant-order", worlds: mutantVariant))
        return lines.joined(separator: "\n") + "\n"
    }

    private static func fixture(
        deviceID: DeviceID,
        scheduleID: ScheduleID,
        builds: [BuildConfiguration],
        locales: [LocaleScenario],
        appearances: [Appearance],
        permissions: [PermissionScenario],
        mutants: [MutantSelection]
    ) -> WorldSpace {
        WorldSpace(
            builds: .enumerated(builds),
            operatingSystems: .enumerated([.iOS]),
            devices: .enumerated([DeviceProfile(id: deviceID, family: .phone)]),
            locales: .enumerated(locales),
            layoutDirections: .enumerated([.leftToRight]),
            appearances: .enumerated(appearances),
            accessibilityScenarios: .enumerated([.standard]),
            permissions: .enumerated(permissions),
            locations: .enumerated([.fixed]),
            biometrics: .enumerated([.succeeds]),
            lifecycles: .enumerated([.foreground]),
            dataScenarios: .enumerated([.typical]),
            serviceFaults: .enumerated([.none]),
            cancellations: .enumerated([.never]),
            schedules: .enumerated([ScheduleScenario(id: scheduleID, decisions: [])]),
            mutants: .enumerated(mutants)
        )
    }

    private static func sequence(in space: WorldSpace) throws(WorldCursorOracleError) -> WorldSequence {
        do {
            return try space.allWorlds()
        } catch let error {
            throw .space(error)
        }
    }

    private static func parsed(_ id: WorldID) throws(WorldCursorOracleError) -> ParsedWorldID {
        let parts = id.rawValue.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "world", parts[1] == "v1",
            let baseOrdinal = UInt(parts[3]) else {
            throw .worldID(id)
        }
        let definition: Digest
        do {
            definition = try Digest.parse(String(parts[2]))
        } catch let error {
            throw .digest(error)
        }
        return ParsedWorldID(definition: definition, baseOrdinal: baseOrdinal)
    }

    private static func digest(_ payload: Data) throws(WorldCursorOracleError) -> Digest {
        do {
            return try Digest.sha256(payload)
        } catch let error {
            throw .digest(error)
        }
    }

    private static func preimageLine(
        _ name: String,
        worlds: WorldSequence
    ) throws(WorldCursorOracleError) -> String {
        try requireDefinitionIDs(
            worlds.lazy.map(\.id),
            expectedCount: worlds.count,
            expectedDefinition: digest(worlds.definitionPayload)
        )
        return [
            "world-definition-preimage", name,
            worlds.definitionPayload.map { String($0) }.joined(separator: ","),
        ].joined(separator: "\t")
    }

    static func requireDefinitionIDs<IDs: Sequence>(
        _ ids: IDs,
        expectedCount: Int,
        expectedDefinition: Digest
    ) throws(WorldCursorOracleError) where IDs.Element == WorldID {
        var observedCount = 0
        for id in ids {
            guard try parsed(id).definition == expectedDefinition else {
                throw .definitionDigestMismatch(id)
            }
            observedCount += 1
        }
        guard observedCount == expectedCount, observedCount > 0 else {
            throw .unexpectedCardinality
        }
    }

    private static func index<Value: Hashable & Sendable>(
        _ value: Value,
        in values: [Value],
        axis: WorldCursorOracleError.Coordinate
    ) throws(WorldCursorOracleError) -> Int {
        guard let index = values.firstIndex(of: value) else {
            throw .missingCoordinate(axis)
        }
        return index
    }
}
