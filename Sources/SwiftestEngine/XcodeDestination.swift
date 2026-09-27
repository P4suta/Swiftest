import Foundation

public enum XcodeDestinationError: Error, Equatable, Sendable {
    case empty
    case malformed(String)
    case duplicateKey(String)
    case unknownKey(String)
    case missingKey(String)
    case unsupportedPlatform(String)
    case invalidValue(String)
    case deviceMismatch(String)
}

enum XcodeDestinationPlatform: String, CaseIterable, Sendable {
    case macOS
    case iOS
    case iOSSimulator = "iOS Simulator"
    case tvOS
    case tvOSSimulator = "tvOS Simulator"
    case watchOS
    case watchOSSimulator = "watchOS Simulator"
    case visionOS
    case visionOSSimulator = "visionOS Simulator"
}

struct XcodeDestinationDeviceID: Equatable, Sendable {
    let rawValue: String

    private init(rawValue: String) {
        self.rawValue = rawValue
    }

    static func parse(_ text: String) throws(XcodeDestinationError) -> XcodeDestinationDeviceID {
        guard !text.isEmpty,
            text.utf8.allSatisfy({
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
            }),
            text.contains(where: { $0.isNumber }) else {
            throw .invalidValue("id")
        }
        return XcodeDestinationDeviceID(rawValue: text)
    }
}

struct XcodeDestination: Equatable, Sendable {
    let platform: XcodeDestinationPlatform
    let id: XcodeDestinationDeviceID
    let name: String?
    let osVersion: String?
    let rawValue: String

    private init(
        platform: XcodeDestinationPlatform,
        id: XcodeDestinationDeviceID,
        name: String?,
        osVersion: String?
    ) {
        self.platform = platform
        self.id = id
        self.name = name
        self.osVersion = osVersion
        var values = ["platform=" + platform.rawValue, "id=" + id.rawValue]
        if let name {
            values.append("name=" + name)
        }
        if let osVersion {
            values.append("OS=" + osVersion)
        }
        self.rawValue = values.joined(separator: ",")
    }

    static func parse(_ text: String) throws(XcodeDestinationError) -> XcodeDestination {
        guard !text.isEmpty else {
            throw .empty
        }
        let components = text.split(separator: ",", omittingEmptySubsequences: false)
        var fields: [String: String] = [:]
        for component in components {
            let pair = component.split(separator: "=", omittingEmptySubsequences: false)
            guard pair.count == 2, !pair[0].isEmpty, !pair[1].isEmpty else {
                throw .malformed(String(component))
            }
            let key = String(pair[0])
            let value = String(pair[1])
            guard ["platform", "id", "name", "OS"].contains(key) else {
                throw .unknownKey(key)
            }
            guard fields[key] == nil else {
                throw .duplicateKey(key)
            }
            fields[key] = value
        }
        guard let platformText = fields["platform"] else {
            throw .missingKey("platform")
        }
        guard let platform = XcodeDestinationPlatform(rawValue: platformText) else {
            throw .unsupportedPlatform(platformText)
        }
        guard let identifier = fields["id"] else {
            throw .missingKey("id")
        }
        let id = try XcodeDestinationDeviceID.parse(identifier)
        let name: String?
        if let value = fields["name"] {
            guard validName(value) else {
                throw .invalidValue("name")
            }
            name = value
        } else {
            name = nil
        }
        let osVersion: String?
        if let value = fields["OS"] {
            let parts = value.split(separator: ".", omittingEmptySubsequences: false)
            guard (2...3).contains(parts.count),
                parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy({ (48...57).contains($0) }) }) else {
                throw .invalidValue("OS")
            }
            osVersion = value
        } else {
            osVersion = nil
        }
        return XcodeDestination(platform: platform, id: id, name: name, osVersion: osVersion)
    }

    func verify(device: XcodeDeviceIdentity) throws(XcodeDestinationError) {
        guard device.platform == platform.rawValue else {
            throw .deviceMismatch("platform")
        }
        guard device.deviceID == id.rawValue else {
            throw .deviceMismatch("id")
        }
        if let name, device.deviceName != name {
            throw .deviceMismatch("name")
        }
        if let osVersion, device.osVersion != osVersion {
            throw .deviceMismatch("OS")
        }
    }

    private static func validName(_ value: String) -> Bool {
        !value.isEmpty
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.contains("$")
            && !value.contains("/")
            && !value.contains("\\")
            && !value.contains("%")
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
}
