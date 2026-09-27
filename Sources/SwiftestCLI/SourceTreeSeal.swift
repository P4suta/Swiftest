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

    static func captureLeased(root: String) throws(SourceTreeSealError) -> LeasedSourceTree {
        var files: [String] = []
        var directories: [String] = []
        try collect(root: root, relative: "", files: &files, directories: &directories)
        var inputs = [WatchedInput(path: root, kind: .directory)]
        inputs.append(contentsOf: directories.sorted().map {
            WatchedInput(path: root + "/" + $0, kind: .directory)
        })
        inputs.append(contentsOf: files.sorted().map {
            WatchedInput(path: root + "/" + $0, kind: .file)
        })
        let lease: FileEventLease
        do {
            lease = try FileEventLease(inputs: inputs)
        } catch let error {
            throw .platform(error)
        }
        let seal = try capture(root: root)
        if directories.sorted() != seal.directories || files.sorted() != seal.files.keys.sorted() {
            throw .changed("watched-input-inventory")
        }
        let initialContinuity: FileEventContinuity
        do {
            initialContinuity = try lease.verifyUnchanged()
        } catch let error {
            throw .platform(error)
        }
        return LeasedSourceTree(seal: seal, lease: lease, initialContinuity: initialContinuity)
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
        var manifest = EvidenceTranscript()
        manifest.append("source-tree-v2")
        manifest.append(String(directories.count))
        for directory in directories {
            manifest.append(directory)
        }
        manifest.append(String(files.count))
        for name in files.keys.sorted() {
            guard let file = files[name] else {
                throw .changed(name)
            }
            manifest.append(name)
            manifest.append(file.digest.rawValue)
            manifest.append(String(file.mode.rawValue))
        }
        do {
            return try manifest.digest()
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
                if relative.isEmpty && child == SourceExcludedDirectory.swiftConfiguration.rawValue {
                    throw .unsupportedEntry(child)
                }
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

struct LeasedSourceTree: ~Copyable {
    let seal: SourceTreeSeal
    private let lease: FileEventLease
    private let initialContinuity: FileEventContinuity

    init(
        seal: SourceTreeSeal,
        lease: consuming FileEventLease,
        initialContinuity: FileEventContinuity
    ) {
        self.seal = seal
        self.lease = lease
        self.initialContinuity = initialContinuity
    }

    borrowing func observeUnchanged() throws(SourceTreeSealError) -> FileEventWitness {
        let before: FileEventWitness
        do {
            before = try lease.observeUnchanged()
        } catch let error {
            throw .platform(error)
        }
        try seal.verifyUnchanged()
        let after: FileEventWitness
        do {
            after = try lease.observeUnchanged()
        } catch let error {
            throw .platform(error)
        }
        return after.including(initialContinuity.joined(with: before.continuity))
    }

    borrowing func verifyUnchanged() throws(SourceTreeSealError) -> FileEventContinuity {
        try observeUnchanged().continuity
    }
}
