import Darwin
import Foundation

enum ABIAdapter {
    struct DirectoryIdentity: Equatable, Sendable {
        let device: UInt64
        let inode: UInt64
    }

    enum EntryPresence {
        case absent
        case present
        case unavailable
    }

    enum OutputCreation {
        case created(Int32)
        case present
        case unavailable
    }

    static func canonicalPath(_ path: String) -> String? {
        if path.utf8.contains(0) {
            return nil
        }
        guard let pointer = path.withCString({ source in Darwin.realpath(source, nil) }) else {
            return nil
        }
        defer {
            Darwin.free(pointer)
        }
        return String(validatingCString: pointer)
    }

    static func inputDirectoryIdentity(at path: String) -> DirectoryIdentity? {
        if path.utf8.contains(0) {
            return nil
        }
        var finalPath = path
        while finalPath.count > 1 && finalPath.hasSuffix("/") {
            finalPath.removeLast()
        }
        var before = stat()
        if Darwin.lstat(finalPath, &before) != 0 || !isDirectory(before) {
            return nil
        }
        let descriptor = Darwin.open(finalPath, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0 {
            return nil
        }
        defer {
            closeOrTerminate(descriptor)
        }
        var opened = stat()
        if Darwin.fstat(descriptor, &opened) != 0 || !isDirectory(opened) {
            return nil
        }
        let initial = identity(before)
        return initial == identity(opened) ? initial : nil
    }

    static func canonicalDirectoryIdentity(at path: String) -> DirectoryIdentity? {
        if path.utf8.contains(0) || !path.hasPrefix("/") {
            return nil
        }
        let descriptor = openDirectoryWithoutSymlinks(at: path)
        if descriptor < 0 {
            return nil
        }
        defer {
            closeOrTerminate(descriptor)
        }
        var opened = stat()
        if Darwin.fstat(descriptor, &opened) != 0 || !isDirectory(opened) {
            return nil
        }
        return identity(opened)
    }

    private static func isDirectory(_ value: stat) -> Bool {
        value.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
    }

    private static func identity(_ value: stat) -> DirectoryIdentity {
        DirectoryIdentity(
            device: UInt64(bitPattern: Int64(value.st_dev)),
            inode: UInt64(value.st_ino)
        )
    }

    static func openDirectoryWithoutSymlinks(at absolutePath: String) -> Int32 {
        let flags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        let root = Darwin.open("/", flags)
        if root < 0 {
            return root
        }
        var descriptor = root
        for component in absolutePath.split(separator: "/") {
            let next = String(component).withCString { name in
                Darwin.openat(descriptor, name, flags)
            }
            if next < 0 {
                let failure = errno
                closeOrTerminate(descriptor)
                errno = failure
                return -1
            }
            closeOrTerminate(descriptor)
            descriptor = next
        }
        return descriptor
    }

    static func presence(of name: String, in parent: Int32) -> EntryPresence {
        var attributes = stat()
        let status = name.withCString { pointer in
            Darwin.fstatat(parent, pointer, &attributes, AT_SYMLINK_NOFOLLOW)
        }
        if status == 0 {
            return .present
        }
        if errno == ENOENT {
            return .absent
        }
        return .unavailable
    }

    static func openNewOutput(named name: String, in parent: Int32) -> OutputCreation {
        let descriptor = name.withCString { pointer in
            Darwin.openat(
                parent,
                pointer,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                S_IRUSR | S_IWUSR
            )
        }
        if descriptor >= 0 {
            return .created(descriptor)
        }
        if errno == EEXIST {
            return .present
        }
        return .unavailable
    }

    static func writeAll(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let base = bytes.baseAddress else {
                return bytes.isEmpty
            }
            var offset = 0
            while offset < bytes.count {
                let remaining = bytes.count - offset
                let amount = min(remaining, 1_048_576)
                let count = Darwin.write(descriptor, base.advanced(by: offset), amount)
                if count < 0 {
                    if errno == EINTR {
                        continue
                    }
                    return false
                }
                if count == 0 {
                    return false
                }
                offset += count
            }
            return true
        }
    }

    static func synchronize(_ descriptor: Int32) -> Bool {
        Darwin.fsync(descriptor) == 0
    }

    static func closeOrTerminate(_ descriptor: Int32) {
        let status = Darwin.close(descriptor)
        if status != 0 {
            Darwin.exit(2)
        }
    }

    static func openLock(at path: String) -> Int32 {
        Darwin.open(path, O_CREAT | O_EXCL | O_RDWR, S_IRUSR | S_IWUSR)
    }

    static func releaseLock(_ descriptor: Int32, path: String) {
        let closeResult = Darwin.close(descriptor)
        let unlinkResult = Darwin.unlink(path)
        if closeResult == Int32.min || unlinkResult == Int32.min {
            preconditionFailure("unreachable release status")
        }
    }

    static func monotonicNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    static func terminateFailure(_ message: String) -> Never {
        let stdoutStatus = Darwin.fflush(Darwin.stdout)
        let stderrStatus = message.withCString { pointer in
            Darwin.fputs(pointer, Darwin.stderr)
        }
        if stdoutStatus != 0 || stderrStatus < 0 {
            Darwin.exit(2)
        }
        Darwin.exit(1)
    }
}
