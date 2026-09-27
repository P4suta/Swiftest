import Foundation
import SwiftestModel

public enum PlatformError: Error, Equatable, Sendable {
    case invalidRoot(String)
    case pathEscapesRoot(String)
    case createDirectory(String)
    case scratchOwnershipLost(String)
    case read(String)
    case watch(String)
    case changedWhileWatched(String)
    case attributeAmbiguous(WatchedPath)
    case attributeOriginMissing
    case eventGenerationOverflow
    case lateInputEvent
    case write(String)
    case remove(String)
    case move(String, String)
    case lockOpen(String, Int32)
    case lockBusy(String, Int32)
    case processLaunch(String)
    case processExit(String, Int32, String)
    case processTimedOut(String)
    case processCancelled(String)
    case processInputLimit(String)
    case processOutputLimit(String)
    case processTerminationFailed(String)
    case invalidOutput(String)
    case outputExists(String)
    case outputDurabilityUnconfirmed(String)
    case unsupportedPlatform(String)
}

public struct WatchedPath: Equatable, Sendable {
    public let rawValue: String

    private init(rawValue: String) {
        self.rawValue = rawValue
    }

    static func validated(_ candidate: String) -> WatchedPath? {
        let components = candidate.split(separator: "/", omittingEmptySubsequences: false)
        guard !candidate.utf8.contains(0), components.first == "", components.count > 1,
            components.dropFirst().allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        return WatchedPath(rawValue: candidate)
    }
}

public enum FileEntryKind: String, CaseIterable, Sendable {
    case file
    case directory
    case symbolicLink = "symbolic-link"
    case other
}

public enum OptionalDirectoryListing: Equatable, Sendable {
    case absent
    case entries([String])
}

public struct FileMode: Equatable, Sendable {
    public let rawValue: UInt16

    private init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    static func observed(_ value: UInt16) -> FileMode {
        FileMode(rawValue: value)
    }
}

public struct WriteCapability: ~Copyable {
    let root: String
    let descriptor: Int32

    init(root: String, descriptor: Int32) {
        self.root = root
        self.descriptor = descriptor
    }

    deinit {
        ABIAdapter.closeOrTerminate(descriptor)
    }
}

public enum FileSystemAuthority {
    public static func grant(root: String) throws(PlatformError) -> WriteCapability {
        guard root.hasPrefix("/"), let canonical = ABIAdapter.canonicalPath(root) else {
            throw .invalidRoot(root)
        }
        let descriptor = ABIAdapter.openDirectoryWithoutSymlinks(at: canonical)
        guard descriptor >= 0 else {
            throw .invalidRoot(root)
        }
        return WriteCapability(root: canonical, descriptor: descriptor)
    }
}

public enum FileSystemBoundary {
    public static func read(path: String) throws(PlatformError) -> Data {
        do {
            return try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw .read(path)
        }
    }

    public static func list(path: String) throws(PlatformError) -> [String] {
        do {
            return try FileManager.default.contentsOfDirectory(atPath: path).sorted()
        } catch {
            throw .read(path)
        }
    }

    public static func listIfPresent(path: String) throws(PlatformError) -> OptionalDirectoryListing {
        switch ABIAdapter.directoryPresence(at: path) {
        case .absent:
            return .absent
        case .present:
            return .entries(try list(path: path))
        case .unavailable:
            throw .read(path)
        }
    }

    public static func read(root: String, relativePath: ArtifactPath) throws(PlatformError) -> Data {
        let rootURL = URL(fileURLWithPath: root).standardizedFileURL.resolvingSymlinksInPath()
        let destination = try authorizedURL(relativePath: relativePath, root: rootURL)
        do {
            return try Data(contentsOf: destination)
        } catch {
            throw .read(destination.path)
        }
    }

    public static func entryKind(path: String) throws(PlatformError) -> FileEntryKind {
        let type: FileAttributeType
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            guard let entryType = attributes[.type] as? FileAttributeType else {
                throw PlatformError.read(path)
            }
            type = entryType
        } catch {
            throw .read(path)
        }
        switch type {
        case .typeRegular:
            return .file
        case .typeDirectory:
            return .directory
        case .typeSymbolicLink:
            return .symbolicLink
        default:
            return .other
        }
    }

    public static func mode(path: String) throws(PlatformError) -> FileMode {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            guard let value = attributes[.posixPermissions] as? NSNumber else {
                throw PlatformError.read(path)
            }
            return FileMode.observed(value.uint16Value)
        } catch {
            throw .read(path)
        }
    }

    public static func write(
        _ data: Data,
        relativePath: ArtifactPath,
        capability: consuming WriteCapability
    ) throws(PlatformError) {
        switch ABIAdapter.writeRelative(data, path: relativePath.rawValue, root: capability.descriptor) {
        case .completed:
            return
        case .escaped:
            throw .pathEscapesRoot(relativePath.rawValue)
        case .unavailable:
            throw .write(capability.root + "/" + relativePath.rawValue)
        }
    }

    public static func copyRegularFile(
        from source: String,
        relativePath: ArtifactPath,
        capability: consuming WriteCapability
    ) throws(PlatformError) {
        switch ABIAdapter.copyRelativeRegularFile(
            from: source,
            path: relativePath.rawValue,
            root: capability.descriptor
        ) {
        case .completed:
            return
        case .escaped:
            throw .pathEscapesRoot(relativePath.rawValue)
        case .sourceUnavailable:
            throw .read(source)
        case .destinationUnavailable:
            throw .write(capability.root + "/" + relativePath.rawValue)
        }
    }

    public static func createDirectory(
        relativePath: ArtifactPath,
        capability: consuming WriteCapability
    ) throws(PlatformError) {
        switch ABIAdapter.createRelativeDirectory(path: relativePath.rawValue, root: capability.descriptor) {
        case .completed:
            return
        case .escaped:
            throw .pathEscapesRoot(relativePath.rawValue)
        case .unavailable:
            throw .createDirectory(capability.root + "/" + relativePath.rawValue)
        }
    }

    public static func createSymbolicLink(
        relativePath: ArtifactPath,
        destination: ArtifactPath,
        capability: consuming WriteCapability
    ) throws(PlatformError) {
        switch ABIAdapter.createRelativeSymbolicLink(
            path: relativePath.rawValue,
            target: destination.rawValue,
            root: capability.descriptor
        ) {
        case .completed:
            return
        case .escaped:
            throw .pathEscapesRoot(relativePath.rawValue)
        case .unavailable:
            throw .write(capability.root + "/" + relativePath.rawValue)
        }
    }

    public static func remove(
        relativePath: ArtifactPath,
        capability: consuming WriteCapability
    ) throws(PlatformError) {
        switch ABIAdapter.removeRelative(path: relativePath.rawValue, root: capability.descriptor) {
        case .completed:
            return
        case .escaped:
            throw .pathEscapesRoot(relativePath.rawValue)
        case .unavailable:
            throw .remove(capability.root + "/" + relativePath.rawValue)
        }
    }

    static func authorizedURL(relativePath: ArtifactPath, root: URL) throws(PlatformError) -> URL {
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let destination = root.appendingPathComponent(relativePath.rawValue).standardizedFileURL
        let prefix = canonicalRoot.path.hasSuffix("/") ? canonicalRoot.path : canonicalRoot.path + "/"
        var resolved = canonicalRoot
        for component in relativePath.rawValue.split(separator: "/") {
            resolved = resolved.appendingPathComponent(String(component)).standardizedFileURL.resolvingSymlinksInPath()
            if !resolved.path.hasPrefix(prefix) {
                throw .pathEscapesRoot(relativePath.rawValue)
            }
        }
        return destination
    }
}

public struct ScratchDirectoryOwner: ~Copyable {
    public let path: String
    private let name: String
    private let parentPath: String
    private let parentIdentity: ABIAdapter.DirectoryIdentity
    private let directoryIdentity: ABIAdapter.DirectoryIdentity
    private let parentDescriptor: Int32
    private let directoryDescriptor: Int32

    public init(parent: String, name: String) throws(PlatformError) {
        let parentComponents = parent.split(separator: "/", omittingEmptySubsequences: false)
        guard parentComponents.first == "", parentComponents.count > 1,
            parentComponents.dropFirst().allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
            !parent.utf8.contains(0) else {
            throw .invalidRoot(parent)
        }
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"),
            !name.utf8.contains(0) else {
            throw .pathEscapesRoot(name)
        }
        guard let expectedParent = ABIAdapter.canonicalDirectoryIdentity(at: parent) else {
            throw .invalidRoot(parent)
        }
        let destination = parent + "/" + name
        switch ABIAdapter.createExclusiveScratchDirectory(
            named: name,
            in: parent,
            expectedParent: expectedParent
        ) {
        case .created(let identity, let parentDescriptor, let directoryDescriptor):
            self.path = destination
            self.name = name
            self.parentPath = parent
            self.parentIdentity = expectedParent
            self.directoryIdentity = identity
            self.parentDescriptor = parentDescriptor
            self.directoryDescriptor = directoryDescriptor
        case .present, .unavailable:
            throw .createDirectory(destination)
        }
    }

    public borrowing func verifyOwnership() throws(PlatformError) {
        guard ABIAdapter.canonicalDirectoryIdentity(at: parentPath) == parentIdentity,
            ABIAdapter.inputDirectoryIdentity(at: path) == directoryIdentity,
            ABIAdapter.directoryIdentity(of: parentDescriptor) == parentIdentity,
            ABIAdapter.directoryIdentity(of: directoryDescriptor) == directoryIdentity else {
            throw .scratchOwnershipLost(path)
        }
    }

    public borrowing func issueWriteCapability() -> WriteCapability {
        do {
            return try issueVerifiedWriteCapability()
        } catch {
            ABIAdapter.terminateFailure("swiftest: scratch ownership lost before capability issuance\n")
        }
    }

    public borrowing func issueVerifiedWriteCapability() throws(PlatformError) -> WriteCapability {
        try verifyOwnership()
        let descriptor = ABIAdapter.duplicateDirectory(directoryDescriptor)
        guard descriptor >= 0 else {
            throw .scratchOwnershipLost(path)
        }
        guard ABIAdapter.directoryIdentity(of: descriptor) == directoryIdentity else {
            ABIAdapter.closeOrTerminate(descriptor)
            throw .scratchOwnershipLost(path)
        }
        do {
            try verifyOwnership()
        } catch {
            ABIAdapter.closeOrTerminate(descriptor)
            throw error
        }
        return WriteCapability(root: path, descriptor: descriptor)
    }

    deinit {
        do {
            try verifyOwnership()
            guard ABIAdapter.removeDirectoryContents(directoryDescriptor) else {
                ABIAdapter.terminateFailure("swiftest: scratch cleanup ownership failure\n")
            }
            try verifyOwnership()
            guard ABIAdapter.removeOwnedScratchDirectory(
                named: name,
                in: parentDescriptor,
                expected: directoryIdentity
            ) else {
                ABIAdapter.terminateFailure("swiftest: scratch cleanup ownership failure\n")
            }
            ABIAdapter.closeOrTerminate(directoryDescriptor)
            ABIAdapter.closeOrTerminate(parentDescriptor)
        } catch {
            ABIAdapter.terminateFailure("swiftest: scratch cleanup ownership failure\n")
        }
    }
}

public struct FileLockOwner: ~Copyable {
    let descriptor: Int32
    public let path: String

    public init(path: String) throws(PlatformError) {
        let descriptor = ABIAdapter.openLock(at: path)
        if descriptor < 0 {
            if errno == EEXIST {
                throw .lockBusy(path, errno)
            }
            throw .lockOpen(path, errno)
        }
        self.descriptor = descriptor
        self.path = path
    }

    deinit {
        ABIAdapter.releaseLock(descriptor, path: path)
    }
}

public struct DeviceLease: ~Copyable {
    public let device: DeviceID
    let lock: FileLockOwner

    public init(device: DeviceID, lockPath: String) throws(PlatformError) {
        self.device = device
        self.lock = try FileLockOwner(path: lockPath)
    }
}

public struct TaskOwner<Success: Sendable>: ~Copyable {
    private let task: Task<Success, Never>

    public init(operation: sending @escaping @isolated(any) () async -> Success) {
        self.task = Task(operation: operation)
    }

    public consuming func value() async -> Success {
        await task.value
    }

    deinit {
        task.cancel()
    }
}

public enum PlatformClock {
    public static func monotonicNanoseconds() -> DurationNanoseconds {
        DurationNanoseconds.measured(ABIAdapter.monotonicNanoseconds())
    }
}

public enum TaskBoundary {
    public static func yield() async {
        await Task.yield()
    }
}

public enum EnvironmentBoundary {
    public static func value(for key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }
}

public enum WorkingDirectoryBoundary {
    public static func current() -> String {
        FileManager.default.currentDirectoryPath
    }
}
