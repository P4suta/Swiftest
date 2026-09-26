import Foundation
import SwiftestModel

public enum PlatformError: Error, Equatable, Sendable {
    case invalidRoot(String)
    case pathEscapesRoot(String)
    case createDirectory(String)
    case read(String)
    case write(String)
    case remove(String)
    case move(String, String)
    case lockOpen(String, Int32)
    case lockBusy(String, Int32)
    case processLaunch(String)
    case processExit(String, Int32, String)
    case invalidOutput(String)
    case outputExists(String)
    case unsupportedPlatform(String)
}

public enum FileEntryKind: String, CaseIterable, Sendable {
    case file
    case directory
    case symbolicLink = "symbolic-link"
    case other
}

public struct WriteCapability: ~Copyable {
    let root: URL

    init(root: URL) {
        self.root = root
    }
}

public enum FileSystemAuthority {
    public static func grant(root: String) throws(PlatformError) -> WriteCapability {
        let url = URL(fileURLWithPath: root).standardizedFileURL.resolvingSymlinksInPath()
        if !url.isFileURL {
            throw .invalidRoot(root)
        }
        return WriteCapability(root: url)
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

    public static func write(
        _ data: Data,
        relativePath: ArtifactPath,
        capability: consuming WriteCapability
    ) throws(PlatformError) {
        let destination = try authorizedURL(relativePath: relativePath, root: capability.root)
        let parent = destination.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
        } catch {
            throw .write(destination.path)
        }
    }

    public static func createDirectory(
        relativePath: ArtifactPath,
        capability: consuming WriteCapability
    ) throws(PlatformError) {
        let destination = try authorizedURL(relativePath: relativePath, root: capability.root)
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            throw .createDirectory(destination.path)
        }
    }

    public static func createSymbolicLink(
        relativePath: ArtifactPath,
        destination: ArtifactPath,
        capability: consuming WriteCapability
    ) throws(PlatformError) {
        let link = try authorizedURL(relativePath: relativePath, root: capability.root)
        let target = try authorizedURL(relativePath: destination, root: capability.root)
        do {
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        } catch {
            throw .write(link.path)
        }
    }

    public static func remove(
        relativePath: ArtifactPath,
        capability: consuming WriteCapability
    ) throws(PlatformError) {
        let destination = try authorizedURL(relativePath: relativePath, root: capability.root)
        do {
            try FileManager.default.removeItem(at: destination)
        } catch {
            throw .remove(destination.path)
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

    public init(parent: String, name: String) throws(PlatformError) {
        let parentURL = URL(fileURLWithPath: parent).standardizedFileURL
        let destination = parentURL.appendingPathComponent(name).standardizedFileURL
        let prefix = parentURL.path.hasSuffix("/") ? parentURL.path : parentURL.path + "/"
        if !destination.path.hasPrefix(prefix) {
            throw .pathEscapesRoot(name)
        }
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        } catch {
            throw .createDirectory(destination.path)
        }
        self.path = destination.path
    }

    public borrowing func issueWriteCapability() -> WriteCapability {
        WriteCapability(root: URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath())
    }

    deinit {
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch {
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
