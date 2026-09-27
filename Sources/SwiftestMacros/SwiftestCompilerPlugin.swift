import Foundation
import SwiftestCodec
import SwiftestLaws

private enum MacroWireError: Error, Equatable, Sendable {
    case io
    case unexpectedEnd
    case oversizedMessage
    case invalidPayload
    case missingField(String)
    case unknownField(String)
    case invalidField(String)
    case json(StrictJSONError)
}

private struct WireObject {
    let fields: [String: JSONValue]

    init(_ value: JSONValue, allowed: Set<String>) throws(MacroWireError) {
        guard case .object(let fields) = value else {
            throw .invalidPayload
        }
        for name in fields.keys where !allowed.contains(name) {
            throw .unknownField(name)
        }
        self.fields = fields
    }

    func required(_ name: String) throws(MacroWireError) -> JSONValue {
        guard let value = fields[name] else {
            throw .missingField(name)
        }
        return value
    }

    func string(_ name: String) throws(MacroWireError) -> String {
        guard case .string(let value) = try required(name) else {
            throw .invalidField(name)
        }
        return value
    }

    func integer(_ name: String) throws(MacroWireError) -> Int {
        guard case .number(let text) = try required(name), let value = Int(text) else {
            throw .invalidField(name)
        }
        return value
    }
}

private struct MacroLocation {
    let fileName: String
    let offset: Int

    init(_ value: JSONValue) throws(MacroWireError) {
        let object = try WireObject(value, allowed: ["fileID", "fileName", "offset", "line", "column"])
        self.fileName = try object.string("fileName")
        self.offset = try object.integer("offset")
        let fileID = try object.string("fileID")
        let line = try object.integer("line")
        let column = try object.integer("column")
        guard fileID.utf8.count <= 4_096, line >= 0, column >= 0, offset >= 0 else {
            throw .invalidField("location")
        }
    }
}

private struct MacroSyntax {
    let source: String
    let location: MacroLocation

    init(_ value: JSONValue) throws(MacroWireError) {
        let object = try WireObject(value, allowed: ["kind", "source", "location"])
        let kind = try object.string("kind")
        guard ["declaration", "statement", "expression", "type", "pattern", "attribute", "accessor"].contains(kind) else {
            throw .invalidField("kind")
        }
        self.source = try object.string("source")
        self.location = try MacroLocation(object.required("location"))
    }
}

private enum MacroRequest {
    case capability
    case expansion(typeName: String, role: String, syntax: MacroSyntax, attributeSource: String, parentSource: String?)

    init(_ value: JSONValue) throws(MacroWireError) {
        let outer = try WireObject(value, allowed: ["getCapability", "expandAttachedMacro", "expandFreestandingMacro"])
        guard outer.fields.count == 1, let entry = outer.fields.first else {
            throw .invalidPayload
        }
        switch entry.key {
        case "getCapability":
            let request = try WireObject(entry.value, allowed: ["capability"])
            if let capability = request.fields["capability"], capability != .null {
                let host = try WireObject(capability, allowed: ["protocolVersion"])
                let version = try host.integer("protocolVersion")
                guard version >= 1 else {
                    throw .invalidField("protocolVersion")
                }
            }
            self = .capability
        case "expandAttachedMacro":
            let request = try WireObject(entry.value, allowed: [
                "macro", "macroRole", "discriminator", "attributeSyntax", "declSyntax",
                "parentDeclSyntax", "extendedTypeSyntax", "conformanceListSyntax",
                "lexicalContext", "staticBuildConfiguration",
            ])
            let macro = try Self.macroReference(request.required("macro"))
            let role = try request.string("macroRole")
            let discriminator = try request.string("discriminator")
            let attribute = try MacroSyntax(request.required("attributeSyntax"))
            let syntax = try MacroSyntax(request.required("declSyntax"))
            let parent = try Self.optionalSyntaxSource(request, name: "parentDeclSyntax")
            try Self.validateOptionalSyntax(request, name: "extendedTypeSyntax")
            try Self.validateOptionalSyntax(request, name: "conformanceListSyntax")
            try Self.validateSharedFields(request)
            guard !discriminator.isEmpty, !attribute.source.isEmpty else {
                throw .invalidField("attributeSyntax")
            }
            self = .expansion(
                typeName: macro,
                role: role,
                syntax: syntax,
                attributeSource: attribute.source,
                parentSource: parent
            )
        case "expandFreestandingMacro":
            let request = try WireObject(entry.value, allowed: [
                "macro", "macroRole", "discriminator", "syntax", "lexicalContext",
                "staticBuildConfiguration",
            ])
            let macro = try Self.macroReference(request.required("macro"))
            let discriminator = try request.string("discriminator")
            let syntax = try MacroSyntax(request.required("syntax"))
            try Self.validateSharedFields(request)
            guard !discriminator.isEmpty else {
                throw .invalidField("discriminator")
            }
            let role: String
            if let roleValue = request.fields["macroRole"], roleValue != .null {
                guard case .string(let name) = roleValue else {
                    throw .invalidField("macroRole")
                }
                role = name
            } else {
                role = "expression"
            }
            self = .expansion(typeName: macro, role: role, syntax: syntax, attributeSource: "", parentSource: nil)
        default:
            throw .invalidPayload
        }
    }

    private static func macroReference(_ value: JSONValue) throws(MacroWireError) -> String {
        let object = try WireObject(value, allowed: ["moduleName", "typeName", "name"])
        guard try object.string("moduleName") == "SwiftestMacros" else {
            throw .invalidField("moduleName")
        }
        let typeName = try object.string("typeName")
        let name = try object.string("name")
        guard !name.isEmpty else {
            throw .invalidField("name")
        }
        return typeName
    }

    private static func validateOptionalSyntax(
        _ request: WireObject,
        name: String
    ) throws(MacroWireError) {
        let source = try optionalSyntaxSource(request, name: name)
        if let source, source.isEmpty {
            throw .invalidField(name)
        }
    }

    private static func optionalSyntaxSource(
        _ request: WireObject,
        name: String
    ) throws(MacroWireError) -> String? {
        if let value = request.fields[name], value != .null {
            let syntax = try MacroSyntax(value)
            guard !syntax.source.isEmpty else {
                throw .invalidField(name)
            }
            return syntax.source
        }
        return nil
    }

    private static func validateSharedFields(_ request: WireObject) throws(MacroWireError) {
        if let value = request.fields["lexicalContext"], value != .null {
            guard case .array(let values) = value else {
                throw .invalidField("lexicalContext")
            }
            for item in values {
                let syntax = try MacroSyntax(item)
                guard !syntax.source.isEmpty else {
                    throw .invalidField("lexicalContext")
                }
            }
        }
        if let value = request.fields["staticBuildConfiguration"], value != .null {
            guard case .string(let text) = value else {
                throw .invalidField("staticBuildConfiguration")
            }
            let configuration: JSONValue
            do {
                configuration = try StrictJSON.decode(Data(text.utf8))
            } catch let error {
                throw .json(error)
            }
            guard case .object = configuration else {
                throw .invalidField("staticBuildConfiguration")
            }
        }
    }
}

private enum MacroResponse {
    static func capability() -> JSONValue {
        .object([
            "getCapabilityResult": .object([
                "capability": .object([
                    "features": .array([]),
                    "protocolVersion": .number("8"),
                ]),
            ]),
        ])
    }

    static func expansion(_ source: String) -> JSONValue {
        .object([
            "expandMacroResult": .object([
                "expandedSource": .string(source),
                "diagnostics": .array([]),
            ]),
        ])
    }

    static func error(_ message: String, location: MacroLocation) -> JSONValue {
        .object([
            "expandMacroResult": .object([
                "expandedSource": .null,
                "diagnostics": .array([
                    .object([
                        "message": .string(message),
                        "severity": .string("error"),
                        "position": .object([
                            "fileName": .string(location.fileName),
                            "offset": .number(String(location.offset)),
                        ]),
                        "highlights": .array([]),
                        "notes": .array([]),
                        "fixIts": .array([]),
                    ]),
                ]),
            ]),
        ])
    }
}

private struct MacroWireConnection {
    private let input = FileHandle.standardInput
    private let output = FileHandle.standardOutput

    func next() throws(MacroWireError) -> JSONValue? {
        guard let header = try read(count: 8) else {
            return nil
        }
        var length: UInt64 = 0
        for (index, byte) in header.enumerated() {
            length |= UInt64(byte) << (index * 8)
        }
        if length == 0 {
            return nil
        }
        guard let count = Int(exactly: length), count <= 268_435_456 else {
            throw .oversizedMessage
        }
        guard let payload = try read(count: count) else {
            throw .unexpectedEnd
        }
        do {
            return try StrictJSON.decode(payload)
        } catch let error {
            throw .json(error)
        }
    }

    func send(_ value: JSONValue) throws(MacroWireError) {
        let payload = StrictJSON.encode(value)
        let length = UInt64(payload.count)
        var header = Data()
        for index in 0..<8 {
            header.append(UInt8(truncatingIfNeeded: length >> (index * 8)))
        }
        do {
            try output.write(contentsOf: header)
            try output.write(contentsOf: payload)
        } catch {
            throw .io
        }
    }

    private func read(count: Int) throws(MacroWireError) -> Data? {
        var result = Data()
        while result.count < count {
            let part: Data?
            do {
                part = try input.read(upToCount: count - result.count)
            } catch {
                throw .io
            }
            guard let part, !part.isEmpty else {
                if result.isEmpty {
                    return nil
                }
                throw .unexpectedEnd
            }
            result.append(part)
        }
        return result
    }
}

@main
private enum SwiftestCompilerPlugin {
    static func main() throws(MacroWireError) {
        let connection = MacroWireConnection()
        while let payload = try connection.next() {
            let request = try MacroRequest(payload)
            let response: JSONValue
            switch request {
            case .capability:
                response = MacroResponse.capability()
            case .expansion(let typeName, let role, let syntax, let attributeSource, let parentSource):
                do {
                    let expanded = try SwiftestMacroExpansion.expand(
                        typeName: typeName,
                        role: role,
                        source: syntax.source,
                        attributeSource: attributeSource,
                        parentSource: parentSource
                    )
                    if let expansionRole = MacroExpansionRole(rawValue: role) {
                        switch MacroExpansionLawGate.inspect(expanded, role: expansionRole) {
                        case .accepted:
                            response = MacroResponse.expansion(expanded)
                        case .rejected(let violations):
                            let codes = Set(violations.map { $0.law.rawValue }).sorted().joined(separator: ",")
                            response = MacroResponse.error(
                                "macro expansion violates Swiftest laws: " + codes,
                                location: syntax.location
                            )
                        }
                    } else {
                        response = MacroResponse.error("unknown macro expansion role", location: syntax.location)
                    }
                } catch let error {
                    response = MacroResponse.error(error.message, location: syntax.location)
                }
            }
            try connection.send(response)
        }
    }
}
