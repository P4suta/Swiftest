import Swiftest
import SwiftestPlatform

enum SourceSnapshotError: Error {
    case scratchInsideSource(String)
    case path(ArtifactPathError)
    case platform(PlatformError)
    case seal(SourceTreeSealError)
}

struct SourceSnapshot: ~Copyable {
    private let scratch: ScratchDirectoryOwner
    private let originalRoot: String
    let root: String
    let seal: SourceTreeSeal

    init(source: SourceTreeSeal) throws(SourceSnapshotError) {
        let parent = "/private/tmp"
        if parent == source.root || parent.hasPrefix(source.root + "/") {
            throw .scratchInsideSource(source.root)
        }
        let scratch: ScratchDirectoryOwner
        do {
            scratch = try ScratchDirectoryOwner(
                parent: parent,
                name: "swiftest-source-" + String(PlatformClock.monotonicNanoseconds().rawValue)
            )
        } catch let error {
            throw .platform(error)
        }
        let root = scratch.path + "/source"
        do {
            let sourcePath = try ArtifactPath.parse("source")
            try FileSystemBoundary.createDirectory(
                relativePath: sourcePath,
                capability: scratch.issueWriteCapability()
            )
            for relative in source.directories {
                let path = try ArtifactPath.parse("source/" + relative)
                try FileSystemBoundary.createDirectory(
                    relativePath: path,
                    capability: scratch.issueWriteCapability()
                )
            }
            for relative in source.files.keys.sorted() {
                let path = try ArtifactPath.parse("source/" + relative)
                try FileSystemBoundary.copyRegularFile(
                    from: source.root + "/" + relative,
                    relativePath: path,
                    capability: scratch.issueWriteCapability()
                )
            }
        } catch let error as ArtifactPathError {
            throw .path(error)
        } catch let error as PlatformError {
            throw .platform(error)
        } catch {
            throw .platform(.write(root))
        }
        let captured: SourceTreeSeal
        do {
            captured = try SourceTreeSeal.capture(root: root)
            try source.assertSameTree(as: captured)
        } catch let error {
            throw .seal(error)
        }
        self.scratch = scratch
        self.originalRoot = source.root
        self.root = root
        self.seal = captured
    }

    borrowing func verifyUnchanged() throws(SourceSnapshotError) {
        do {
            try seal.verifyUnchanged()
        } catch let error {
            throw .seal(error)
        }
    }

    borrowing func rebasedContainer(_ path: String?) -> String? {
        guard let path, path.hasPrefix("/") else {
            return path
        }
        if path == originalRoot {
            return root
        }
        let originalPrefix = originalRoot + "/"
        if path.hasPrefix(originalPrefix) {
            return root + String(path.dropFirst(originalRoot.count))
        }
        return path
    }
}
