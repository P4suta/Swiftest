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
    let directories: [String]
    let files: [String: SealedFile]

    struct SealedFile: Equatable {
        let digest: Digest
        let mode: FileMode
    }

    static func capture(root: String) throws(SourceTreeSealError) -> SourceTreeSeal {
        var files: [String] = []
        var directories: [String] = []
        try collect(root: root, relative: "", files: &files, directories: &directories)
        var captured: [String: SealedFile] = [:]
        for relative in files.sorted() {
            let data: Data
            let mode: FileMode
            do {
                data = try FileSystemBoundary.read(path: root + "/" + relative)
                mode = try FileSystemBoundary.mode(path: root + "/" + relative)
            } catch let error {
                throw .platform(error)
            }
            do {
                captured[relative] = SealedFile(digest: try Digest.sha256(data), mode: mode)
            } catch let error {
                throw .digest(error)
            }
        }
        return SourceTreeSeal(root: root, directories: directories.sorted(), files: captured)
    }

    func verifyUnchanged() throws(SourceTreeSealError) {
        let after = try Self.capture(root: root)
        try assertSameTree(as: after)
    }

    func assertSameTree(as after: SourceTreeSeal) throws(SourceTreeSealError) {
        if directories != after.directories {
            throw .changed("directories")
        }
        let names = Set(files.keys).union(after.files.keys)
        for name in names.sorted() where files[name] != after.files[name] {
            throw .changed(name)
        }
    }

    func manifestDigest() throws(SourceTreeSealError) -> Digest {
        var manifest = Data()
        for directory in directories {
            manifest.append(68)
            manifest.append(contentsOf: String(directory.utf8.count).utf8)
            manifest.append(58)
            manifest.append(contentsOf: directory.utf8)
        }
        for name in files.keys.sorted() {
            guard let file = files[name] else {
                throw .changed(name)
            }
            manifest.append(70)
            manifest.append(contentsOf: String(name.utf8.count).utf8)
            manifest.append(58)
            manifest.append(contentsOf: name.utf8)
            manifest.append(contentsOf: file.digest.rawValue.utf8)
            manifest.append(58)
            manifest.append(contentsOf: String(file.mode.rawValue).utf8)
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
        files: inout [String],
        directories: inout [String]
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
                if relative.isEmpty && SourceExclusionPolicy.excludesDirectory(relativePath: child) {
                    continue
                }
                directories.append(child)
                try collect(root: root, relative: child, files: &files, directories: &directories)
            case .symbolicLink, .other:
                throw .unsupportedEntry(child)
            }
        }
    }
}
