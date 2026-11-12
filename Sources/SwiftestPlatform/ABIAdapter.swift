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

    enum OutputInstallation {
        case installed
        case present
        case unavailable
    }

    enum ScratchCreation {
        case created(DirectoryIdentity, parent: Int32, directory: Int32)
        case present
        case unavailable
    }

    enum RelativeOperation {
        case completed
        case escaped
        case unavailable
    }

    enum RelativeDirectory {
        case opened(Int32)
        case escaped
        case unavailable
    }

    enum RelativeParent {
        case opened(Int32, String)
        case escaped
        case unavailable
    }

    enum RelativeCopy {
        case completed
        case escaped
        case sourceUnavailable
        case destinationUnavailable
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

    static func directoryIdentity(of descriptor: Int32) -> DirectoryIdentity? {
        var attributes = stat()
        guard Darwin.fstat(descriptor, &attributes) == 0, isDirectory(attributes) else {
            return nil
        }
        return identity(attributes)
    }

    static func duplicateDirectory(_ descriptor: Int32) -> Int32 {
        Darwin.openat(descriptor, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
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

    static func directoryPresence(at path: String) -> EntryPresence {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else {
            return .unavailable
        }
        var attributes = stat()
        let status = path.withCString { Darwin.lstat($0, &attributes) }
        if status != 0 {
            return errno == ENOENT ? .absent : .unavailable
        }
        guard isDirectory(attributes) else {
            return .unavailable
        }
        let descriptor = openDirectoryWithoutSymlinks(at: path)
        if descriptor >= 0 {
            closeOrTerminate(descriptor)
            return .present
        }
        return .unavailable
    }

    static func createExclusiveScratchDirectory(
        named name: String,
        in parentPath: String,
        expectedParent: DirectoryIdentity
    ) -> ScratchCreation {
        let parent = openDirectoryWithoutSymlinks(at: parentPath)
        if parent < 0 {
            return .unavailable
        }
        var openedParent = stat()
        if Darwin.fstat(parent, &openedParent) != 0 || identity(openedParent) != expectedParent {
            closeOrTerminate(parent)
            return .unavailable
        }
        let created = name.withCString { pointer in
            Darwin.mkdirat(parent, pointer, S_IRWXU)
        }
        if created != 0 {
            let failure = errno
            closeOrTerminate(parent)
            return failure == EEXIST ? .present : .unavailable
        }
        let directory = name.withCString { pointer in
            Darwin.openat(parent, pointer, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard directory >= 0, let directoryIdentity = directoryIdentity(of: directory) else {
            if directory >= 0 {
                closeOrTerminate(directory)
            }
            closeOrTerminate(parent)
            return .unavailable
        }
        var namedChild = stat()
        let inspected = name.withCString { pointer in
            Darwin.fstatat(parent, pointer, &namedChild, AT_SYMLINK_NOFOLLOW)
        }
        guard inspected == 0, isDirectory(namedChild), identity(namedChild) == directoryIdentity else {
            closeOrTerminate(directory)
            closeOrTerminate(parent)
            return .unavailable
        }
        return .created(directoryIdentity, parent: parent, directory: directory)
    }

    static func openRelativeDirectory(
        root: Int32,
        components: [String],
        creating: Bool
    ) -> RelativeDirectory {
        var current = duplicateDirectory(root)
        guard current >= 0 else {
            return .unavailable
        }
        let flags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        for component in components {
            var next = component.withCString { Darwin.openat(current, $0, flags) }
            if next < 0 && creating && errno == ENOENT {
                let created = component.withCString { Darwin.mkdirat(current, $0, S_IRWXU) }
                if created == 0 || errno == EEXIST {
                    next = component.withCString { Darwin.openat(current, $0, flags) }
                }
            }
            if next < 0 {
                let failure = errno
                closeOrTerminate(current)
                return failure == ELOOP || failure == ENOTDIR ? .escaped : .unavailable
            }
            closeOrTerminate(current)
            current = next
        }
        return .opened(current)
    }

    static func openRelativeParent(root: Int32, path: String, creating: Bool) -> RelativeParent {
        let components = path.split(separator: "/").map(String.init)
        guard let name = components.last else {
            return .unavailable
        }
        switch openRelativeDirectory(root: root, components: Array(components.dropLast()), creating: creating) {
        case .opened(let descriptor):
            return .opened(descriptor, name)
        case .escaped:
            return .escaped
        case .unavailable:
            return .unavailable
        }
    }

    static func writeRelative(_ data: Data, path: String, root: Int32) -> RelativeOperation {
        switch openRelativeParent(root: root, path: path, creating: true) {
        case .escaped:
            return .escaped
        case .unavailable:
            return .unavailable
        case .opened(let parent, let name):
            defer {
                closeOrTerminate(parent)
            }
            guard let temporary = openTemporaryOutput(in: parent) else {
                return .unavailable
            }
            let written = writeAll(data, to: temporary.descriptor)
            let synchronized = written && synchronize(temporary.descriptor)
            closeOrTerminate(temporary.descriptor)
            guard synchronized else {
                unlinkOutputOrTerminate(named: temporary.name, in: parent)
                return .unavailable
            }
            let installed = temporary.name.withCString { source in
                name.withCString { destination in
                    Darwin.renameat(parent, source, parent, destination)
                }
            }
            if installed != 0 {
                unlinkOutputOrTerminate(named: temporary.name, in: parent)
                return .unavailable
            }
            return .completed
        }
    }

    static func createRelativeDirectory(path: String, root: Int32) -> RelativeOperation {
        let components = path.split(separator: "/").map(String.init)
        switch openRelativeDirectory(root: root, components: components, creating: true) {
        case .opened(let descriptor):
            closeOrTerminate(descriptor)
            return .completed
        case .escaped:
            return .escaped
        case .unavailable:
            return .unavailable
        }
    }

    static func createRelativeSymbolicLink(path: String, target: String, root: Int32) -> RelativeOperation {
        switch openRelativeParent(root: root, path: target, creating: false) {
        case .opened(let parent, let name):
            defer {
                closeOrTerminate(parent)
            }
            var attributes = stat()
            let inspected = name.withCString { Darwin.fstatat(parent, $0, &attributes, AT_SYMLINK_NOFOLLOW) }
            if inspected == 0 && attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFLNK) {
                return .escaped
            }
            if inspected != 0 && errno != ENOENT {
                return .unavailable
            }
        case .escaped:
            return .escaped
        case .unavailable:
            return .unavailable
        }
        switch openRelativeParent(root: root, path: path, creating: false) {
        case .escaped:
            return .escaped
        case .unavailable:
            return .unavailable
        case .opened(let parent, let name):
            defer {
                closeOrTerminate(parent)
            }
            let depth = path.split(separator: "/").count - 1
            let relativeTarget = Array(repeating: "..", count: depth).joined(separator: "/")
            let linkText = relativeTarget.isEmpty ? target : relativeTarget + "/" + target
            let status = linkText.withCString { targetPointer in
                name.withCString { namePointer in
                    Darwin.symlinkat(targetPointer, parent, namePointer)
                }
            }
            return status == 0 ? .completed : .unavailable
        }
    }

    static func copyRelativeRegularFile(from source: String, path: String, root: Int32) -> RelativeCopy {
        let sourceDescriptor = openRegularSourceWithoutSymlinks(source)
        guard sourceDescriptor >= 0 else {
            return .sourceUnavailable
        }
        defer {
            closeOrTerminate(sourceDescriptor)
        }
        var sourceAttributes = stat()
        guard Darwin.fstat(sourceDescriptor, &sourceAttributes) == 0,
            sourceAttributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            return .sourceUnavailable
        }
        switch openRelativeParent(root: root, path: path, creating: true) {
        case .escaped:
            return .escaped
        case .unavailable:
            return .destinationUnavailable
        case .opened(let parent, let name):
            defer {
                closeOrTerminate(parent)
            }
            switch openNewOutput(named: name, in: parent) {
            case .present, .unavailable:
                return .destinationUnavailable
            case .created(let destination):
                var copied = true
                var buffer = [UInt8](repeating: 0, count: 65_536)
                while copied {
                    let amount = buffer.withUnsafeMutableBytes { bytes in
                        Darwin.read(sourceDescriptor, bytes.baseAddress, bytes.count)
                    }
                    if amount == 0 {
                        break
                    }
                    if amount < 0 {
                        if errno == EINTR {
                            continue
                        }
                        copied = false
                        break
                    }
                    copied = buffer.withUnsafeBytes { bytes in
                        guard let base = bytes.baseAddress else {
                            return false
                        }
                        var offset = 0
                        while offset < amount {
                            let written = Darwin.write(destination, base.advanced(by: offset), amount - offset)
                            if written < 0 && errno == EINTR {
                                continue
                            }
                            if written <= 0 {
                                return false
                            }
                            offset += written
                        }
                        return true
                    }
                }
                if copied {
                    copied = Darwin.fchmod(destination, sourceAttributes.st_mode & mode_t(0o777)) == 0
                        && synchronize(destination)
                }
                closeOrTerminate(destination)
                if !copied {
                    unlinkOutputOrTerminate(named: name, in: parent)
                }
                return copied ? .completed : .destinationUnavailable
            }
        }
    }

    private static func openRegularSourceWithoutSymlinks(_ source: String) -> Int32 {
        guard source.hasPrefix("/"), !source.utf8.contains(0),
            let slash = source.lastIndex(of: "/"),
            source.index(after: slash) != source.endIndex else {
            return -1
        }
        let parentPath = slash == source.startIndex ? "/" : String(source[..<slash])
        let name = String(source[source.index(after: slash)...])
        let parent = openDirectoryWithoutSymlinks(at: parentPath)
        guard parent >= 0 else {
            return -1
        }
        let descriptor = name.withCString {
            Darwin.openat(parent, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        closeOrTerminate(parent)
        return descriptor
    }

    static func removeRelative(path: String, root: Int32) -> RelativeOperation {
        switch openRelativeParent(root: root, path: path, creating: false) {
        case .escaped:
            return .escaped
        case .unavailable:
            return .unavailable
        case .opened(let parent, let name):
            defer {
                closeOrTerminate(parent)
            }
            return removeEntry(named: name, in: parent) ? .completed : .unavailable
        }
    }

    static func removeDirectoryContents(_ descriptor: Int32) -> Bool {
        let listingDescriptor = duplicateDirectory(descriptor)
        guard listingDescriptor >= 0 else {
            return false
        }
        guard let stream = Darwin.fdopendir(listingDescriptor) else {
            closeOrTerminate(listingDescriptor)
            return false
        }
        var removed = true
        while removed {
            errno = 0
            guard let entry = Darwin.readdir(stream) else {
                removed = errno == 0
                break
            }
            let name = withUnsafePointer(to: entry.pointee.d_name) { storage in
                storage.withMemoryRebound(to: CChar.self, capacity: 1) {
                    String(validatingCString: $0)
                }
            }
            guard let name else {
                removed = false
                break
            }
            if name == "." || name == ".." {
                continue
            }
            removed = removeEntry(named: name, in: descriptor)
        }
        if Darwin.closedir(stream) != 0 {
            return false
        }
        return removed
    }

    static func removeOwnedScratchDirectory(
        named name: String,
        in parent: Int32,
        expected: DirectoryIdentity
    ) -> Bool {
        var attributes = stat()
        let inspected = name.withCString { Darwin.fstatat(parent, $0, &attributes, AT_SYMLINK_NOFOLLOW) }
        guard inspected == 0, isDirectory(attributes), identity(attributes) == expected else {
            return false
        }
        return name.withCString { Darwin.unlinkat(parent, $0, AT_REMOVEDIR) } == 0
    }

    private static func removeEntry(named name: String, in parent: Int32) -> Bool {
        var attributes = stat()
        let inspected = name.withCString { Darwin.fstatat(parent, $0, &attributes, AT_SYMLINK_NOFOLLOW) }
        guard inspected == 0 else {
            return false
        }
        if !isDirectory(attributes) {
            return name.withCString { Darwin.unlinkat(parent, $0, 0) } == 0
        }
        let directory = name.withCString {
            Darwin.openat(parent, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard directory >= 0 else {
            return false
        }
        let openedIdentity = directoryIdentity(of: directory)
        guard openedIdentity == identity(attributes) else {
            closeOrTerminate(directory)
            return false
        }
        let removed = removeDirectoryContents(directory)
        closeOrTerminate(directory)
        guard removed else {
            return false
        }
        var current = stat()
        let verified = name.withCString { Darwin.fstatat(parent, $0, &current, AT_SYMLINK_NOFOLLOW) }
        guard verified == 0, identity(current) == openedIdentity else {
            return false
        }
        return name.withCString { Darwin.unlinkat(parent, $0, AT_REMOVEDIR) } == 0
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

    static func openTemporaryOutput(in parent: Int32) -> (descriptor: Int32, name: String)? {
        for _ in 0..<8 {
            let name = ".swiftest-output-"
                + String(Darwin.arc4random(), radix: 16)
                + "-" + String(Darwin.arc4random(), radix: 16)
                + "-" + String(Darwin.arc4random(), radix: 16)
                + "-" + String(Darwin.arc4random(), radix: 16)
            switch openNewOutput(named: name, in: parent) {
            case .created(let descriptor):
                return (descriptor, name)
            case .present:
                continue
            case .unavailable:
                return nil
            }
        }
        return nil
    }

    static func linkNewOutput(from source: String, to destination: String, in parent: Int32) -> OutputInstallation {
        let status = source.withCString { sourceName in
            destination.withCString { destinationName in
                Darwin.linkat(parent, sourceName, parent, destinationName, 0)
            }
        }
        if status == 0 {
            return .installed
        }
        if errno == EEXIST {
            return .present
        }
        return .unavailable
    }

    static func unlinkOutputOrTerminate(named name: String, in parent: Int32) {
        if name.withCString({ Darwin.unlinkat(parent, $0, 0) }) != 0 {
            Darwin.exit(2)
        }
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

    static func createTemporaryCapture(in directory: String) -> (descriptor: Int32, path: String)? {
        guard !directory.utf8.contains(0) else {
            return nil
        }
        var template = Array((directory + "/swiftest-stderr-XXXXXX").utf8CString)
        let descriptor = template.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else {
                return Int32(-1)
            }
            return Darwin.mkstemp(base)
        }
        guard descriptor >= 0 else {
            return nil
        }
        let bytes = template.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let path = String(decoding: bytes, as: UTF8.self)
        if Darwin.fcntl(descriptor, F_SETFD, FD_CLOEXEC) < 0 {
            let closeStatus = Darwin.close(descriptor)
            let unlinkStatus = path.withCString { Darwin.unlink($0) }
            if closeStatus != 0 || unlinkStatus != 0 {
                Darwin.exit(2)
            }
            return nil
        }
        return (descriptor, path)
    }

    static func unlinkOrTerminate(_ path: String) {
        if path.withCString({ Darwin.unlink($0) }) != 0 {
            Darwin.exit(2)
        }
    }

    static func openLock(at path: String) -> Int32 {
        Darwin.open(path, O_CREAT | O_EXCL | O_RDWR, S_IRUSR | S_IWUSR)
    }

    static func releaseLock(_ descriptor: Int32, path: String) {
        let closeResult = Darwin.close(descriptor)
        let unlinkResult = Darwin.unlink(path)
        if closeResult != 0 || unlinkResult != 0 {
            Darwin.exit(2)
        }
    }

    static func terminateCleanupFailure() -> Never {
        Darwin.exit(2)
    }

    static func forceKill(_ identifier: Int32) -> Bool {
        Darwin.kill(identifier, SIGKILL) == 0 || errno == ESRCH
    }

    static func requestTermination(_ identifier: Int32) -> Bool {
        Darwin.kill(identifier, SIGTERM) == 0 || errno == ESRCH
    }

    static func accountHomeDirectory() -> String? {
        var account = passwd()
        var resolved: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 16_384)
        return buffer.withUnsafeMutableBufferPointer { storage in
            guard let base = storage.baseAddress else {
                return nil
            }
            let status = Darwin.getpwuid_r(Darwin.geteuid(), &account, base, storage.count, &resolved)
            guard status == 0, resolved != nil, let home = account.pw_dir else {
                return nil
            }
            return String(validatingCString: home)
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

    enum VnodeEvent: Equatable {
        case none
        case attributeAmbiguous(WatchedPath)
        case mutation(String)
        case unknownDescriptor
        case unavailable
    }

    enum VnodeRegistration {
        case registered
        case unavailable
    }

    struct FileEventMetadata: Equatable, Sendable {
        let device: UInt64
        let inode: UInt64
        let mode: UInt32
        let size: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        let changedSeconds: Int64
        let changedNanoseconds: Int64
    }

    struct VnodeEventQueue: ~Copyable {
        private struct Registration {
            let path: WatchedPath
            let metadata: FileEventMetadata
        }

        private let descriptor: Int32
        private var registrations: [Int32: Registration] = [:]

        init?() {
            #if os(macOS)
            let opened = Darwin.kqueue()
            guard opened >= 0 else {
                return nil
            }
            guard Darwin.fcntl(opened, F_SETFD, FD_CLOEXEC) >= 0 else {
                ABIAdapter.closeOrTerminate(opened)
                return nil
            }
            descriptor = opened
            #else
            return nil
            #endif
        }

        var registrationCount: Int {
            registrations.count
        }

        mutating func register(_ input: WatchedInput) -> VnodeRegistration {
            #if os(macOS)
            return registerOnDarwin(input)
            #else
            return .unavailable
            #endif
        }

        borrowing func nextEvent() -> VnodeEvent {
            #if os(macOS)
            var event = Darwin.kevent64_s()
            var timeout = timespec(tv_sec: 0, tv_nsec: 0)
            let count = Darwin.kevent64(descriptor, nil, 0, &event, 1, 0, &timeout)
            if count == 0 {
                return .none
            }
            if count < 0 || event.flags & UInt16(EV_ERROR) != 0 {
                return .unavailable
            }
            guard let watchedDescriptor = Int32(exactly: event.ident),
                let registration = registrations[watchedDescriptor] else {
                return .unknownDescriptor
            }
            if event.fflags == UInt32(NOTE_ATTRIB),
                let metadata = ABIAdapter.fileEventMetadata(watchedDescriptor),
                metadata == registration.metadata {
                return .attributeAmbiguous(registration.path)
            }
            return .mutation(registration.path.rawValue)
            #else
            return .unavailable
            #endif
        }

        deinit {
            for watchedDescriptor in registrations.keys {
                ABIAdapter.closeOrTerminate(watchedDescriptor)
            }
            ABIAdapter.closeOrTerminate(descriptor)
        }

        #if os(macOS)
        private mutating func registerOnDarwin(_ input: WatchedInput) -> VnodeRegistration {
            guard let watchedPath = WatchedPath.validated(input.path),
                let slash = input.path.lastIndex(of: "/") else {
                return .unavailable
            }
            let parentPath = slash == input.path.startIndex
                ? "/" : String(input.path[..<slash])
            let name = String(input.path[input.path.index(after: slash)...])
            guard !name.isEmpty else {
                return .unavailable
            }
            let parent = ABIAdapter.openDirectoryWithoutSymlinks(at: parentPath)
            guard parent >= 0 else {
                return .unavailable
            }
            let watchedDescriptor = name.withCString { pointer in
                Darwin.openat(parent, pointer, O_EVTONLY | O_NOFOLLOW | O_CLOEXEC)
            }
            ABIAdapter.closeOrTerminate(parent)
            guard watchedDescriptor >= 0 else {
                return .unavailable
            }
            var attributes = stat()
            guard Darwin.fstat(watchedDescriptor, &attributes) == 0 else {
                ABIAdapter.closeOrTerminate(watchedDescriptor)
                return .unavailable
            }
            let observedKind = attributes.st_mode & mode_t(S_IFMT)
            let expectedKind: mode_t
            switch input.kind {
            case .file:
                expectedKind = mode_t(S_IFREG)
            case .directory:
                expectedKind = mode_t(S_IFDIR)
            }
            guard observedKind == expectedKind else {
                ABIAdapter.closeOrTerminate(watchedDescriptor)
                return .unavailable
            }
            guard let metadata = ABIAdapter.fileEventMetadata(watchedDescriptor) else {
                ABIAdapter.closeOrTerminate(watchedDescriptor)
                return .unavailable
            }
            let mutationFlags = UInt32(
                NOTE_DELETE | NOTE_WRITE | NOTE_EXTEND | NOTE_LINK | NOTE_RENAME | NOTE_REVOKE | NOTE_ATTRIB
            )
            var event = ABIAdapter.makeVnodeRegistration(
                descriptor: watchedDescriptor,
                mutationFlags: mutationFlags
            )
            let status = withUnsafePointer(to: &event) { change in
                Darwin.kevent64(descriptor, change, 1, nil, 0, 0, nil)
            }
            if status != 0 {
                ABIAdapter.closeOrTerminate(watchedDescriptor)
                return .unavailable
            }
            registrations[watchedDescriptor] = Registration(path: watchedPath, metadata: metadata)
            return .registered
        }
        #endif
    }

    #if os(macOS)
    private static func makeVnodeRegistration(descriptor: Int32, mutationFlags: UInt32) -> Darwin.kevent64_s {
        Darwin.kevent64_s(
            ident: UInt64(descriptor),
            filter: Int16(EVFILT_VNODE),
            flags: UInt16(EV_ADD | EV_ENABLE | EV_CLEAR),
            fflags: mutationFlags,
            data: 0,
            udata: 0,
            ext: (0, 0)
        )
    }

    static func fileEventMetadata(_ descriptor: Int32) -> FileEventMetadata? {
        var attributes = stat()
        guard Darwin.fstat(descriptor, &attributes) == 0 else {
            return nil
        }
        return FileEventMetadata(
            device: UInt64(bitPattern: Int64(attributes.st_dev)),
            inode: UInt64(attributes.st_ino),
            mode: UInt32(attributes.st_mode),
            size: Int64(attributes.st_size),
            modifiedSeconds: Int64(attributes.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int64(attributes.st_mtimespec.tv_nsec),
            changedSeconds: Int64(attributes.st_ctimespec.tv_sec),
            changedNanoseconds: Int64(attributes.st_ctimespec.tv_nsec)
        )
    }

    static func volumeAccessTimeUpdates(at path: String) -> VolumeAccessTimeUpdates? {
        volumeMountMetadata(at: path)?.accessTimeUpdates
    }

    static func volumeMountMetadata(at path: String) -> VolumeMountMetadata? {
        let descriptor = openDirectoryWithoutSymlinks(at: path)
        guard descriptor >= 0 else {
            return nil
        }
        defer {
            closeOrTerminate(descriptor)
        }
        var attributes = statfs()
        guard Darwin.fstatfs(descriptor, &attributes) == 0 else {
            return nil
        }
        let updates: VolumeAccessTimeUpdates = attributes.f_flags & UInt32(MNT_NOATIME) == 0 ? .enabled : .disabled
        return withUnsafeBytes(of: attributes.f_mntonname) { bytes -> VolumeMountMetadata? in
            guard let end = bytes.firstIndex(of: 0),
                let mountPoint = String(bytes: bytes[..<end], encoding: .utf8) else {
                return nil
            }
            return VolumeMountMetadata(mountPoint: mountPoint, accessTimeUpdates: updates)
        }
    }
    #else
    static func volumeMountMetadata(at path: String) -> VolumeMountMetadata? {
        nil
    }

    static func volumeAccessTimeUpdates(at path: String) -> VolumeAccessTimeUpdates? {
        nil
    }

    static func fileEventMetadata(_ descriptor: Int32) -> FileEventMetadata? {
        nil
    }
    #endif
}
