import SwiftestPlatform

struct PinnedLeanToolchain: Sendable {
    static let version = "4.34.1"
    static let marker = "leanprover/lean4:v" + version

    let bin: String
    let lake: String
    let lean: String
    let checker: String

    static func resolve() throws(PlatformError) -> PinnedLeanToolchain {
        let home = try CanonicalPathBoundary.currentAccountHomeDirectory()
        let root = home + "/.elan/toolchains/leanprover--lean4---v" + version
        let rootIdentity = try CanonicalPathBoundary.captureDirectoryIdentity(root)
        guard rootIdentity.canonicalPath == root else {
            throw .invalidRoot(root)
        }
        let bin = root + "/bin"
        let binIdentity = try CanonicalPathBoundary.captureDirectoryIdentity(bin)
        guard binIdentity.canonicalPath == bin else {
            throw .invalidRoot(bin)
        }
        return PinnedLeanToolchain(
            bin: bin,
            lake: try executable("lake", in: bin),
            lean: try executable("lean", in: bin),
            checker: try executable("leanchecker", in: bin)
        )
    }

    private static func executable(_ name: String, in bin: String) throws(PlatformError) -> String {
        let path = bin + "/" + name
        let canonical = try CanonicalPathBoundary.existing(path)
        guard canonical == path, try FileSystemBoundary.entryKind(path: path) == .file else {
            throw .invalidRoot(path)
        }
        let mode = try FileSystemBoundary.mode(path: path)
        guard mode.rawValue & 0o111 != 0, mode.rawValue & 0o022 == 0 else {
            throw .invalidRoot(path)
        }
        return path
    }
}
