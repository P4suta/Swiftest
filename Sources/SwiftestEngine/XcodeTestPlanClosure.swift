import Foundation
import SwiftestCodec

struct XcodeVerifiedTarget: Equatable, Sendable {
    let project: String
    let identifier: String
    let name: String
}

enum XcodeBuildConfiguration: String, Equatable, Sendable {
    case debug = "Debug"
    case release = "Release"
}

struct XcodeTestPlanInventory: Equatable, Sendable {
    let configurationName: String
    let targets: [XcodeVerifiedTarget]

    fileprivate init(configurationName: String, targets: [XcodeVerifiedTarget]) {
        self.configurationName = configurationName
        self.targets = targets
    }
}

enum XcodeTestPlanClosure {
    static func decode(_ data: Data) throws(XcodeInputClosureError) -> XcodeTestPlanInventory {
        let document = try codec { try StrictJSON.decode(data) }
        var root = try codec { try JSONObjectReader(document) }
        let configurations = try codec { try root.requiredArray("configurations") }
        let defaultOptions = try codec { try root.requiredValue("defaultOptions") }
        let targets = try codec { try root.requiredArray("testTargets") }
        let version = try codec { try root.requiredInteger("version") }
        try codec { try root.finish() }
        guard version == 1,
            configurations.count == 1,
            !targets.isEmpty else {
            throw .invalidTestPlan("structure")
        }
        try emptyOptions(defaultOptions)
        var configuration = try codec { try JSONObjectReader(configurations[0]) }
        let identifier = try codec { try configuration.requiredString("id") }
        let name = try codec { try configuration.requiredString("name") }
        let options = try codec { try configuration.requiredValue("options") }
        try codec { try configuration.finish() }
        guard validConfigurationID(identifier),
            validName(name) else {
            throw .invalidTestPlan("configuration")
        }
        try emptyOptions(options)
        var verifiedTargets: [XcodeVerifiedTarget] = []
        var targetIdentifiers: Set<String> = []
        for targetValue in targets {
            var targetReader = try codec { try JSONObjectReader(targetValue) }
            let referenceValue = try codec { try targetReader.requiredValue("target") }
            try codec { try targetReader.finish() }
            var referenceReader = try codec { try JSONObjectReader(referenceValue) }
            let containerPath = try codec { try referenceReader.requiredString("containerPath") }
            let targetID = try codec { try referenceReader.requiredString("identifier") }
            let targetName = try codec { try referenceReader.requiredString("name") }
            try codec { try referenceReader.finish() }
            guard containerPath.hasPrefix("container:") else {
                throw .invalidTestPlan("containerPath")
            }
            let project = String(containerPath.dropFirst("container:".count))
            guard project.hasSuffix(".xcodeproj"),
                validName(targetName),
                targetID.count == 24,
                targetID.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) }),
                targetIdentifiers.insert(project + ":" + targetID).inserted else {
                throw .invalidTestPlan("target")
            }
            try XcodeInputClosure.validateRelativeReference(project)
            verifiedTargets.append(XcodeVerifiedTarget(
                project: project,
                identifier: targetID,
                name: targetName
            ))
        }
        return XcodeTestPlanInventory(
            configurationName: name,
            targets: verifiedTargets.sorted {
                if $0.project != $1.project {
                    return $0.project < $1.project
                }
                return $0.identifier < $1.identifier
            }
        )
    }

    private static func emptyOptions(_ value: JSONValue) throws(XcodeInputClosureError) {
        guard case .object(let options) = value, options.isEmpty else {
            throw .invalidTestPlan("options")
        }
    }

    private static func validName(_ name: String) -> Bool {
        !name.isEmpty
            && name == name.trimmingCharacters(in: .whitespacesAndNewlines)
            && !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    private static func validConfigurationID(_ identifier: String) -> Bool {
        let bytes = Array(identifier.utf8)
        guard bytes.count == 36 else {
            return false
        }
        for (index, byte) in bytes.enumerated() {
            switch index {
            case 8, 13, 18, 23:
                if byte != 45 {
                    return false
                }
            default:
                if !(48...57).contains(byte) && !(65...70).contains(byte) {
                    return false
                }
            }
        }
        return true
    }

    private static func codec<Value>(
        _ read: () throws -> Value
    ) throws(XcodeInputClosureError) -> Value {
        do {
            return try read()
        } catch let error as StrictJSONError {
            throw .testPlanCodec(error)
        } catch {
            throw .invalidTestPlan("codec")
        }
    }
}
