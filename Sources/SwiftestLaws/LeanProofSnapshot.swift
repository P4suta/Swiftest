import Foundation
import SwiftestModel
import SwiftestPlatform

enum LeanManifestPresence: Equatable {
    case absent
    case present
}

struct LeanProofInputInventory: Equatable {
    static let configurationFiles = ["lakefile.toml", "lean-toolchain", "SwiftestProofs.lean"]

    let directories: [String]
    let files: [String]
    let manifestPresence: LeanManifestPresence

    var allFiles: [String] {
        let manifestFiles: [String]
        switch manifestPresence {
        case .absent:
            manifestFiles = []
        case .present:
            manifestFiles = ["lake-manifest.json"]
        }
        return (Self.configurationFiles + manifestFiles + files).sorted()
    }

    func includingManifest() -> LeanProofInputInventory {
        LeanProofInputInventory(directories: directories, files: files, manifestPresence: .present)
    }

    static func collect(root: String) throws(LeanTrustError) -> LeanProofInputInventory {
        let rootEntries: [String]
        do {
            rootEntries = try FileSystemBoundary.list(path: root)
        } catch let error {
            throw .platform(error)
        }
        let manifestPresence: LeanManifestPresence = rootEntries.contains("lake-manifest.json")
            ? .present : .absent
        var directories: [String] = []
        var files: [String] = []
        try collectDirectory(
            root: root,
            relative: "SwiftestProofs",
            directories: &directories,
            files: &files
        )
        return LeanProofInputInventory(
            directories: directories.sorted(),
            files: files.sorted(),
            manifestPresence: manifestPresence
        )
    }

    private static func collectDirectory(
        root: String,
        relative: String,
        directories: inout [String],
        files: inout [String]
    ) throws(LeanTrustError) {
        let path = root + "/" + relative
        let kind: FileEntryKind
        do {
            kind = try FileSystemBoundary.entryKind(path: path)
        } catch let error {
            throw .platform(error)
        }
        guard kind == .directory else {
            throw .unexpectedEntry(relative)
        }
        directories.append(relative)
        let entries: [String]
        do {
            entries = try FileSystemBoundary.list(path: path)
        } catch let error {
            throw .platform(error)
        }
        for entry in entries {
            let child = relative + "/" + entry
            let childKind: FileEntryKind
            do {
                childKind = try FileSystemBoundary.entryKind(path: root + "/" + child)
            } catch let error {
                throw .platform(error)
            }
            switch childKind {
            case .file:
                guard child.hasSuffix(".lean") else {
                    throw .unexpectedEntry(child)
                }
                files.append(child)
            case .directory:
                try collectDirectory(root: root, relative: child, directories: &directories, files: &files)
            case .symbolicLink, .other:
                throw .unexpectedEntry(child)
            }
        }
    }
}

public enum LeanEventPhase: CaseIterable, Equatable, Sendable {
    case sourceRegistered
    case sourceCaptured
    case snapshotCopied
    case snapshotTrusted
    case sourceAfterSnapshotTrust
    case sourceBeforeRevalidation
    case snapshotBeforeRevalidation
    case sourceAfterRevalidation
    case snapshotAfterRevalidation
    case buildArtifactsRegistered
    case buildArtifactsCaptured
    case buildArtifactsBeforeRevalidation
    case buildArtifactsAfterRevalidation
}

public enum LeanProofSnapshotError: Error, Equatable, Sendable {
    case platform(PlatformError)
    case attributeAmbiguity(LeanEventPhase, WatchedPath)
    case trust(LeanTrustError)
    case path(ArtifactPathError)
    case digest(DigestError)
    case changed(String)
}

enum LeanEventContinuity {
    static func map(_ error: PlatformError, at phase: LeanEventPhase) -> LeanProofSnapshotError {
        if case .attributeAmbiguous(let path) = error {
            return .attributeAmbiguity(phase, path)
        }
        return .platform(error)
    }

    static func requireEventFree(
        _ lease: borrowing FileEventLease,
        at phase: LeanEventPhase
    ) throws(LeanProofSnapshotError) {
        do {
            try lease.requireEventFree()
        } catch let error {
            throw map(error, at: phase)
        }
    }
}

struct LeanProofSnapshot: ~Copyable {
    private struct SealedInput {
        let inventory: LeanProofInputInventory
        let bytes: [String: Data]
        let digests: [String: Digest]

        private init(inventory: LeanProofInputInventory, bytes: [String: Data], digests: [String: Digest]) {
            self.inventory = inventory
            self.bytes = bytes
            self.digests = digests
        }

        static func capture(root: String, inventory: LeanProofInputInventory) throws(LeanProofSnapshotError) -> SealedInput {
            let captured = try LeanProofSnapshot.capture(root: root, inventory: inventory)
            return SealedInput(inventory: inventory, bytes: captured.bytes, digests: captured.digests)
        }

        func insertingGeneratedManifest() throws(LeanProofSnapshotError) -> SealedInput {
            guard inventory.manifestPresence == .absent else {
                throw .changed("manifest-already-present")
            }
            let manifest = LeanTrust.canonicalManifest
            var bytes = bytes
            var digests = digests
            bytes["lake-manifest.json"] = manifest
            do {
                digests["lake-manifest.json"] = try Digest.sha256(manifest)
            } catch let error {
                throw .digest(error)
            }
            return SealedInput(inventory: inventory.includingManifest(), bytes: bytes, digests: digests)
        }
    }

    private let scratch: ScratchDirectoryOwner
    private let sourceIdentity: CanonicalDirectoryIdentity
    private let snapshotIdentity: CanonicalDirectoryIdentity
    private let sourceLease: FileEventLease
    private let snapshotLease: FileEventLease
    private let sourceInput: SealedInput
    private let snapshotInput: SealedInput
    let root: String
    let proofModules: [String]

    init(sourceRoot: String) throws(LeanProofSnapshotError) {
        let sourceIdentity = try Self.directoryIdentity(sourceRoot)
        let source = sourceIdentity.canonicalPath
        let inventory = try Self.collect(root: source)
        let proofModules = try Self.moduleNames(for: inventory)
        let sourceLease = try Self.lease(root: source, inventory: inventory)
        try LeanEventContinuity.requireEventFree(sourceLease, at: .sourceRegistered)
        let sourceInput = try SealedInput.capture(root: source, inventory: inventory)
        try Self.verifyClosure(root: source, input: sourceInput)
        try LeanEventContinuity.requireEventFree(sourceLease, at: .sourceCaptured)

        let snapshotInput: SealedInput
        switch inventory.manifestPresence {
        case .absent:
            snapshotInput = try sourceInput.insertingGeneratedManifest()
        case .present:
            snapshotInput = sourceInput
        }
        let scratch = try Self.makeScratch()
        let snapshotPath = scratch.path + "/source"
        try Self.writeSnapshot(snapshotInput, scratch: scratch)
        let snapshotIdentity = try Self.directoryIdentity(snapshotPath)
        let root = snapshotIdentity.canonicalPath
        try Self.verifySnapshotRoot(root: root)
        let snapshotLease = try Self.lease(root: root, inventory: snapshotInput.inventory)
        try Self.verifyClosure(root: root, input: snapshotInput)
        try LeanEventContinuity.requireEventFree(snapshotLease, at: .snapshotCopied)
        do {
            try LeanTrust.audit(root: root)
            try LeanTrust.auditManifest(root: root)
        } catch let error {
            throw .trust(error)
        }
        try Self.verifyClosure(root: root, input: snapshotInput)
        try LeanEventContinuity.requireEventFree(snapshotLease, at: .snapshotTrusted)
        try LeanEventContinuity.requireEventFree(sourceLease, at: .sourceAfterSnapshotTrust)

        self.scratch = scratch
        self.sourceIdentity = sourceIdentity
        self.snapshotIdentity = snapshotIdentity
        self.sourceLease = sourceLease
        self.snapshotLease = snapshotLease
        self.sourceInput = sourceInput
        self.snapshotInput = snapshotInput
        self.root = root
        self.proofModules = proofModules
    }

    borrowing func verifyUnchanged() throws(LeanProofSnapshotError) {
        do {
            try sourceIdentity.verifyCurrentLocation()
            try snapshotIdentity.verifyCurrentLocation()
        } catch let error {
            throw .platform(error)
        }
        try LeanEventContinuity.requireEventFree(sourceLease, at: .sourceBeforeRevalidation)
        try LeanEventContinuity.requireEventFree(snapshotLease, at: .snapshotBeforeRevalidation)
        try Self.verifyClosure(root: sourceIdentity.canonicalPath, input: sourceInput)
        try Self.verifySnapshotRoot(root: root)
        try Self.verifyClosure(root: root, input: snapshotInput)
        try LeanEventContinuity.requireEventFree(sourceLease, at: .sourceAfterRevalidation)
        try LeanEventContinuity.requireEventFree(snapshotLease, at: .snapshotAfterRevalidation)
    }

    borrowing func runPinnedLean(
        toolchain: PinnedLeanToolchain,
        arguments: [String],
        standardInput: Data? = nil
    ) throws(PlatformError) -> ProcessOutput {
        try ProcessBoundary.runPinnedLean(
            toolchainBin: toolchain.bin,
            executable: toolchain.lake,
            arguments: arguments,
            workingDirectory: root,
            scratch: scratch,
            standardInput: standardInput
        )
    }

    private static func moduleNames(
        for inventory: LeanProofInputInventory
    ) throws(LeanProofSnapshotError) -> [String] {
        var modules = ["SwiftestProofs"]
        for relative in inventory.files {
            let stem = relative.dropLast(".lean".count)
            let components = stem.split(separator: "/", omittingEmptySubsequences: false)
            guard components.count > 1, components.first == "SwiftestProofs" else {
                throw .changed("proof-module:" + relative)
            }
            for component in components {
                let bytes = Array(component.utf8)
                guard let first = bytes.first,
                    (first >= 65 && first <= 90) || (first >= 97 && first <= 122) || first == 95,
                    bytes.dropFirst().allSatisfy({ byte in
                        (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
                            || (byte >= 48 && byte <= 57) || byte == 95
                    }) else {
                    throw .changed("proof-module:" + relative)
                }
            }
            modules.append(components.map(String.init).joined(separator: "."))
        }
        guard modules.contains("SwiftestProofs.Oracle"), Set(modules).count == modules.count else {
            throw .changed("proof-module-inventory")
        }
        return modules
    }

    private static func directoryIdentity(_ path: String) throws(LeanProofSnapshotError) -> CanonicalDirectoryIdentity {
        do {
            return try CanonicalPathBoundary.captureDirectoryIdentity(path)
        } catch let error {
            throw .platform(error)
        }
    }

    private static func collect(root: String) throws(LeanProofSnapshotError) -> LeanProofInputInventory {
        do {
            return try LeanProofInputInventory.collect(root: root)
        } catch let error {
            throw .trust(error)
        }
    }

    private static func lease(
        root: String,
        inventory: LeanProofInputInventory
    ) throws(LeanProofSnapshotError) -> FileEventLease {
        var inputs = [WatchedInput(path: root, kind: .directory)]
        inputs.append(contentsOf: inventory.directories.map {
            WatchedInput(path: root + "/" + $0, kind: .directory)
        })
        inputs.append(contentsOf: inventory.allFiles.map {
            WatchedInput(path: root + "/" + $0, kind: .file)
        })
        do {
            return try FileEventLease(inputs: inputs)
        } catch let error {
            throw .platform(error)
        }
    }

    private static func capture(
        root: String,
        inventory: LeanProofInputInventory
    ) throws(LeanProofSnapshotError) -> (bytes: [String: Data], digests: [String: Digest]) {
        var bytes: [String: Data] = [:]
        var digests: [String: Digest] = [:]
        for relative in inventory.allFiles {
            let path = root + "/" + relative
            let data: Data
            do {
                guard try FileSystemBoundary.entryKind(path: path) == .file else {
                    throw LeanProofSnapshotError.changed(relative)
                }
                data = try FileSystemBoundary.read(path: path)
            } catch let error as LeanProofSnapshotError {
                throw error
            } catch let error as PlatformError {
                throw .platform(error)
            } catch {
                throw .changed(relative)
            }
            bytes[relative] = data
            do {
                digests[relative] = try Digest.sha256(data)
            } catch let error {
                throw .digest(error)
            }
        }
        return (bytes, digests)
    }

    private static func verifyClosure(
        root: String,
        input: SealedInput
    ) throws(LeanProofSnapshotError) {
        guard try collect(root: root) == input.inventory else {
            throw .changed("proof-inventory")
        }
        let current = try capture(root: root, inventory: input.inventory)
        guard current.digests == input.digests else {
            throw .changed("proof-bytes")
        }
    }

    private static func verifySnapshotRoot(root: String) throws(LeanProofSnapshotError) {
        let entries: [String]
        do {
            entries = try FileSystemBoundary.list(path: root)
        } catch let error {
            throw .platform(error)
        }
        guard entries == [".lake", "SwiftestProofs", "SwiftestProofs.lean", "lake-manifest.json", "lakefile.toml", "lean-toolchain"] else {
            throw .changed("snapshot-root-entries")
        }
        let kind: FileEntryKind
        do {
            kind = try FileSystemBoundary.entryKind(path: root + "/.lake")
        } catch let error {
            throw .platform(error)
        }
        guard kind == .directory else {
            throw .changed("snapshot-lake-directory")
        }
    }

    private static func makeScratch() throws(LeanProofSnapshotError) -> ScratchDirectoryOwner {
        do {
            return try ScratchDirectoryOwner(
                parent: "/private/tmp",
                name: "swiftest-proof-" + String(PlatformClock.monotonicNanoseconds().rawValue)
            )
        } catch let error {
            throw .platform(error)
        }
    }

    private static func writeSnapshot(
        _ input: SealedInput,
        scratch: borrowing ScratchDirectoryOwner
    ) throws(LeanProofSnapshotError) {
        for relative in ["source"] + input.inventory.directories.map({ "source/" + $0 }) + ["source/.lake"] {
            let path: ArtifactPath
            do {
                path = try ArtifactPath.parse(relative)
            } catch let error {
                throw .path(error)
            }
            do {
                try FileSystemBoundary.createDirectory(
                    relativePath: path,
                    capability: scratch.issueWriteCapability()
                )
            } catch let error {
                throw .platform(error)
            }
        }
        for relative in input.inventory.allFiles {
            guard let data = input.bytes[relative] else {
                throw .changed(relative)
            }
            let path: ArtifactPath
            do {
                path = try ArtifactPath.parse("source/" + relative)
            } catch let error {
                throw .path(error)
            }
            do {
                try FileSystemBoundary.write(
                    data,
                    relativePath: path,
                    capability: scratch.issueWriteCapability()
                )
            } catch let error {
                throw .platform(error)
            }
        }
    }
}

struct LeanBuildArtifactSeal: ~Copyable {
    private struct SealedArtifact: Equatable {
        let digest: Digest
        let mode: FileMode
    }

    private let root: String
    private let directories: [String]
    private let artifacts: [String: SealedArtifact]
    private let lease: FileEventLease

    init(root: String) throws(LeanProofSnapshotError) {
        let inventory = try Self.capture(root: root)
        guard !inventory.files.isEmpty else {
            throw .changed("empty-lean-build")
        }
        var inputs = [WatchedInput(path: root + "/.lake", kind: .directory)]
        inputs.append(contentsOf: inventory.directories.map {
            WatchedInput(path: root + "/" + $0, kind: .directory)
        })
        inputs.append(contentsOf: inventory.files.map {
            WatchedInput(path: root + "/" + $0, kind: .file)
        })
        let lease = try Self.makeLease(inputs: inputs)
        try LeanEventContinuity.requireEventFree(lease, at: .buildArtifactsRegistered)
        let after = try Self.capture(root: root)
        guard after.directories == inventory.directories, after.artifacts == inventory.artifacts else {
            throw .changed("lean-build-capture")
        }
        try LeanEventContinuity.requireEventFree(lease, at: .buildArtifactsCaptured)
        self.root = root
        self.directories = inventory.directories
        self.artifacts = inventory.artifacts
        self.lease = lease
    }

    private static func makeLease(inputs: [WatchedInput]) throws(LeanProofSnapshotError) -> FileEventLease {
        do {
            return try FileEventLease(inputs: inputs)
        } catch let error {
            throw .platform(error)
        }
    }

    borrowing func verifyUnchanged() throws(LeanProofSnapshotError) {
        try LeanEventContinuity.requireEventFree(lease, at: .buildArtifactsBeforeRevalidation)
        let after = try Self.capture(root: root)
        guard after.directories == directories, after.artifacts == artifacts else {
            throw .changed("lean-build-artifacts")
        }
        try LeanEventContinuity.requireEventFree(lease, at: .buildArtifactsAfterRevalidation)
    }

    private static func capture(
        root: String
    ) throws(LeanProofSnapshotError) -> (directories: [String], files: [String], artifacts: [String: SealedArtifact]) {
        let lakeEntries: [String]
        do {
            lakeEntries = try FileSystemBoundary.list(path: root + "/.lake")
        } catch let error {
            throw .platform(error)
        }
        guard lakeEntries == ["build"] else {
            throw .changed("lean-build-root")
        }
        var directories: [String] = []
        var files: [String] = []
        try collectDirectory(
            root: root,
            relative: ".lake/build",
            directories: &directories,
            files: &files
        )
        var artifacts: [String: SealedArtifact] = [:]
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
                artifacts[relative] = SealedArtifact(digest: try Digest.sha256(data), mode: mode)
            } catch let error {
                throw .digest(error)
            }
        }
        return (directories.sorted(), files.sorted(), artifacts)
    }

    private static func collectDirectory(
        root: String,
        relative: String,
        directories: inout [String],
        files: inout [String]
    ) throws(LeanProofSnapshotError) {
        let directory = root + "/" + relative
        let kind: FileEntryKind
        do {
            kind = try FileSystemBoundary.entryKind(path: directory)
        } catch let error {
            throw .platform(error)
        }
        guard kind == .directory else {
            throw .changed(relative)
        }
        directories.append(relative)
        let entries: [String]
        do {
            entries = try FileSystemBoundary.list(path: directory)
        } catch let error {
            throw .platform(error)
        }
        for entry in entries {
            let child = relative + "/" + entry
            let childKind: FileEntryKind
            do {
                childKind = try FileSystemBoundary.entryKind(path: root + "/" + child)
            } catch let error {
                throw .platform(error)
            }
            switch childKind {
            case .file:
                files.append(child)
            case .directory:
                try collectDirectory(root: root, relative: child, directories: &directories, files: &files)
            case .symbolicLink, .other:
                throw .changed(child)
            }
        }
    }
}
