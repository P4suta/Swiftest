import Foundation
import SwiftestModel
import SwiftestPlatform

public enum SnapshotError: Error, Equatable, Sendable {
    case platform(PlatformError)
    case digest(DigestError)
    case mismatch(expected: Digest, actual: Digest)
}

public enum SnapshotEngine {
    public static func verify(
        value: Data,
        root: String,
        path: ArtifactPath
    ) throws(SnapshotError) {
        let expectedData: Data
        do {
            expectedData = try FileSystemBoundary.read(root: root, relativePath: path)
        } catch let error {
            throw .platform(error)
        }
        let expected: Digest
        let actual: Digest
        do {
            expected = try Digest.sha256(expectedData)
            actual = try Digest.sha256(value)
        } catch let error {
            throw .digest(error)
        }
        if expected != actual {
            throw .mismatch(expected: expected, actual: actual)
        }
    }

    public static func record(
        value: Data,
        path: ArtifactPath,
        capability: consuming WriteCapability
    ) throws(SnapshotError) -> Digest {
        let digest: Digest
        do {
            digest = try Digest.sha256(value)
        } catch let error {
            throw .digest(error)
        }
        do {
            try FileSystemBoundary.write(value, relativePath: path, capability: capability)
        } catch let error {
            throw .platform(error)
        }
        return digest
    }
}
