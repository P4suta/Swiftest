import Foundation
import Swiftest
import SwiftestPlatform

enum SourceTreeSealError: Error {
    case platform(PlatformError)
    case digest(DigestError)
    case unsupportedEntry(String)
    case changed(String)
}

struct SourceTreeSeal {
    let root: String
    let digests: [String: Digest]

    static func capture(root: String) throws(SourceTreeSealError) -> SourceTreeSeal {
        var files: [String] = []
        try collect(root: root, relative: "", into: &files)
        var digests: [String: Digest] = [:]
        for relative in files.sorted() {
            let data: Data
            do {
                data = try FileSystemBoundary.read(path: root + "/" + relative)
            } catch let error {
                throw .platform(error)
            }
            do {
                digests[relative] = try Digest.sha256(data)
            } catch let error {
                throw .digest(error)
            }
        }
        return SourceTreeSeal(root: root, digests: digests)
    }

    func verifyUnchanged() throws(SourceTreeSealError) {
        let after = try Self.capture(root: root)
        let names = Set(digests.keys).union(after.digests.keys)
        for name in names.sorted() where digests[name] != after.digests[name] {
            throw .changed(name)
        }
    }

    func manifestDigest() throws(SourceTreeSealError) -> Digest {
        var manifest = Data()
        for name in digests.keys.sorted() {
            guard let digest = digests[name] else {
                throw .changed(name)
            }
            manifest.append(contentsOf: String(name.utf8.count).utf8)
            manifest.append(58)
            manifest.append(contentsOf: name.utf8)
            manifest.append(contentsOf: digest.rawValue.utf8)
        }
        do {
            return try Digest.sha256(manifest)
        } catch let error {
            throw .digest(error)
        }
    }

    private static func collect(
        root: String,
        relative: String,
        into files: inout [String]
    ) throws(SourceTreeSealError) {
        let directory = relative.isEmpty ? root : root + "/" + relative
        let names: [String]
        do {
            names = try FileSystemBoundary.list(path: directory)
        } catch let error {
            throw .platform(error)
        }
        for name in names {
            let child = relative.isEmpty ? name : relative + "/" + name
            if relative.isEmpty && excludedDirectoryNames.contains(name) {
                continue
            }
            let kind: FileEntryKind
            do {
                kind = try FileSystemBoundary.entryKind(path: root + "/" + child)
            } catch let error {
                throw .platform(error)
            }
            switch kind {
            case .file:
                files.append(child)
            case .directory:
                try collect(root: root, relative: child, into: &files)
            case .symbolicLink, .other:
                throw .unsupportedEntry(child)
            }
        }
    }

    private static let excludedDirectoryNames: Set<String> = [
        ".git", ".build", ".lake", ".swiftpm", "DerivedData",
    ]
}
