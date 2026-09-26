public struct CanonicalDirectoryIdentity: Sendable {
    public let canonicalPath: String
    private let device: UInt64
    private let inode: UInt64

    private init(canonicalPath: String, identity: ABIAdapter.DirectoryIdentity) {
        self.canonicalPath = canonicalPath
        self.device = identity.device
        self.inode = identity.inode
    }

    static func capture(_ path: String) throws(PlatformError) -> CanonicalDirectoryIdentity {
        guard let input = ABIAdapter.inputDirectoryIdentity(at: path),
            let canonical = ABIAdapter.canonicalPath(path),
            let resolved = ABIAdapter.canonicalDirectoryIdentity(at: canonical),
            input == resolved,
            ABIAdapter.inputDirectoryIdentity(at: path) == input else {
            throw .invalidRoot(path)
        }
        return CanonicalDirectoryIdentity(canonicalPath: canonical, identity: input)
    }

    public func verifyCurrentLocation() throws(PlatformError) {
        guard let current = ABIAdapter.canonicalDirectoryIdentity(at: canonicalPath),
            current.device == device,
            current.inode == inode else {
            throw .invalidRoot(canonicalPath)
        }
    }
}

public enum CanonicalPathBoundary {
    public static func directory(_ path: String) throws(PlatformError) -> String {
        guard let canonical = ABIAdapter.canonicalPath(path) else {
            throw .invalidRoot(path)
        }
        return canonical
    }

    public static func captureDirectoryIdentity(
        _ path: String
    ) throws(PlatformError) -> CanonicalDirectoryIdentity {
        try CanonicalDirectoryIdentity.capture(path)
    }
}
