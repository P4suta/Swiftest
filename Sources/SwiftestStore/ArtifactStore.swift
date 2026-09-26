import Foundation
import SwiftestCodec
import SwiftestModel
import SwiftestPlatform

public enum StoreError: Error, Equatable, Sendable {
    case codec(StrictJSONError)
    case digest(DigestError)
    case schema(NumericValueError)
    case platform(PlatformError)
    case digestMismatch(expected: Digest, actual: Digest)
    case unsupportedSchema(SchemaVersion)
}

public struct StoredArtifact: Equatable, Sendable {
    public let schema: SchemaVersion
    public let digest: Digest
    public let payload: JSONValue

    public init(schema: SchemaVersion, digest: Digest, payload: JSONValue) {
        self.schema = schema
        self.digest = digest
        self.payload = payload
    }
}

public enum ArtifactStore {
    public static func write(
        payload: JSONValue,
        relativePath: ArtifactPath,
        capability: consuming WriteCapability
    ) throws(StoreError) -> StoredArtifact {
        let digest: Digest
        do {
            digest = try StrictJSON.canonicalDigest(payload)
        } catch let error {
            throw .digest(error)
        }
        let envelope = JSONValue.object([
            "digest": .string(digest.rawValue),
            "payload": payload,
            "schema": .number(String(SchemaVersion.v1.rawValue)),
        ])
        do {
            try FileSystemBoundary.write(
                StrictJSON.encode(envelope),
                relativePath: relativePath,
                capability: capability
            )
        } catch let error {
            throw .platform(error)
        }
        return StoredArtifact(schema: .v1, digest: digest, payload: payload)
    }

    public static func read(
        root: String,
        relativePath: ArtifactPath
    ) throws(StoreError) -> StoredArtifact {
        let data: Data
        do {
            data = try FileSystemBoundary.read(root: root, relativePath: relativePath)
        } catch let error {
            throw .platform(error)
        }
        let json: JSONValue
        do {
            json = try StrictJSON.decode(data)
        } catch let error {
            throw .codec(error)
        }
        var reader: JSONObjectReader
        do {
            reader = try JSONObjectReader(json)
        } catch let error {
            throw .codec(error)
        }
        let schemaRaw: Int
        let digestRaw: String
        let payload: JSONValue
        do {
            schemaRaw = try reader.requiredInteger("schema")
            digestRaw = try reader.requiredString("digest")
            payload = try reader.requiredValue("payload")
            try reader.finish()
        } catch let error {
            throw .codec(error)
        }
        let schema: SchemaVersion
        do {
            schema = try SchemaVersion.parse(schemaRaw)
        } catch let error {
            throw .schema(error)
        }
        if schema != .v1 {
            throw .unsupportedSchema(schema)
        }
        let expected: Digest
        let actual: Digest
        do {
            expected = try Digest.parse(digestRaw)
            actual = try StrictJSON.canonicalDigest(payload)
        } catch let error {
            throw .digest(error)
        }
        if expected != actual {
            throw .digestMismatch(expected: expected, actual: actual)
        }
        return StoredArtifact(schema: schema, digest: actual, payload: payload)
    }
}
