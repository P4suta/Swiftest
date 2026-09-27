import SwiftestCodec

public enum XcodeRunIdentityError: Error, Equatable, Sendable {
    case codec(StrictJSONError)
    case empty(String)
}

public struct XcodeDeviceIdentity: Equatable, Sendable {
    public let deviceID: String
    public let deviceName: String
    public let architecture: String
    public let modelName: String
    public let platform: String
    public let osVersion: String
    public let osBuildNumber: String?

    private init(
        deviceID: String,
        deviceName: String,
        architecture: String,
        modelName: String,
        platform: String,
        osVersion: String,
        osBuildNumber: String?
    ) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.architecture = architecture
        self.modelName = modelName
        self.platform = platform
        self.osVersion = osVersion
        self.osBuildNumber = osBuildNumber
    }

    static func decode(_ input: JSONValue) throws(XcodeRunIdentityError) -> Self {
        var fields = try IdentityFields(input)
        let deviceID = try fields.required("deviceId")
        let deviceName = try fields.required("deviceName")
        let architecture = try fields.required("architecture")
        let modelName = try fields.required("modelName")
        let platform = try fields.required("platform")
        let osVersion = try fields.required("osVersion")
        let osBuildNumber = try fields.optional("osBuildNumber")
        try fields.finish()
        return Self(
            deviceID: deviceID,
            deviceName: deviceName,
            architecture: architecture,
            modelName: modelName,
            platform: platform,
            osVersion: osVersion,
            osBuildNumber: osBuildNumber
        )
    }
}

public struct XcodeConfigurationIdentity: Equatable, Sendable {
    public let configurationID: String
    public let configurationName: String

    private init(configurationID: String, configurationName: String) {
        self.configurationID = configurationID
        self.configurationName = configurationName
    }

    static func decode(_ input: JSONValue) throws(XcodeRunIdentityError) -> Self {
        var fields = try IdentityFields(input)
        let configurationID = try fields.required("configurationId")
        let configurationName = try fields.required("configurationName")
        try fields.finish()
        return Self(configurationID: configurationID, configurationName: configurationName)
    }
}

private struct IdentityFields {
    private var reader: JSONObjectReader
    private let names: Set<String>

    init(_ input: JSONValue) throws(XcodeRunIdentityError) {
        guard case .object(let fields) = input else {
            throw .codec(.expectedObject)
        }
        self.names = Set(fields.keys)
        do {
            self.reader = try JSONObjectReader(input)
        } catch let error {
            throw .codec(error)
        }
    }

    mutating func required(_ name: String) throws(XcodeRunIdentityError) -> String {
        let value: String
        do {
            value = try reader.requiredString(name)
        } catch let error {
            throw .codec(error)
        }
        guard !value.isEmpty else {
            throw .empty(name)
        }
        return value
    }

    mutating func optional(_ name: String) throws(XcodeRunIdentityError) -> String? {
        guard names.contains(name) else {
            return nil
        }
        return try required(name)
    }

    func finish() throws(XcodeRunIdentityError) {
        do {
            try reader.finish()
        } catch let error {
            throw .codec(error)
        }
    }
}
