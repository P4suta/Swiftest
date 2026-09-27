import Foundation

private struct OwnedDescriptor: ~Copyable {
    let value: Int32

    deinit {
        ABIAdapter.closeOrTerminate(value)
    }
}

private struct StagedOutput: ~Copyable {
    let descriptor: OwnedDescriptor
    let parent: Int32
    let name: String

    init(descriptor: Int32, parent: Int32, name: String) {
        self.descriptor = OwnedDescriptor(value: descriptor)
        self.parent = parent
        self.name = name
    }

    deinit {
        ABIAdapter.unlinkOutputOrTerminate(named: name, in: parent)
    }
}

public struct ExclusiveOutputOwner: ~Copyable {
    private let parent: OwnedDescriptor
    private let name: String
    public let path: String

    public init(absolutePath: String) throws(PlatformError) {
        let components = absolutePath.split(separator: "/", omittingEmptySubsequences: false)
        if components.count < 2 || components.first != "" {
            throw .invalidOutput(absolutePath)
        }
        for component in components.dropFirst() {
            if component.isEmpty || component == "." || component == ".." || component.contains("\0") {
                throw .invalidOutput(absolutePath)
            }
        }
        guard let leaf = components.last else {
            throw .invalidOutput(absolutePath)
        }
        let name = String(leaf)
        let parentComponents = components.dropFirst().dropLast()
        let parentPath = parentComponents.isEmpty ? "/" : "/" + parentComponents.joined(separator: "/")
        let descriptor = ABIAdapter.openDirectoryWithoutSymlinks(at: parentPath)
        if descriptor < 0 {
            throw .invalidOutput(parentPath)
        }
        let owner = OwnedDescriptor(value: descriptor)
        switch ABIAdapter.presence(of: name, in: descriptor) {
        case .absent:
            self.parent = owner
            self.name = name
            self.path = absolutePath
        case .present:
            throw .outputExists(absolutePath)
        case .unavailable:
            throw .invalidOutput(absolutePath)
        }
    }

    public consuming func write(_ data: Data) throws(PlatformError) {
        let destination = path
        do {
            try self.writeValidated(data, validating: {})
        } catch let error as PlatformError {
            throw error
        } catch {
            throw .write(destination)
        }
    }

    public consuming func writeValidated(_ data: Data, validating: () throws -> Void) throws {
        guard let created = ABIAdapter.openTemporaryOutput(in: parent.value) else {
            throw PlatformError.write(path)
        }
        let staged = StagedOutput(descriptor: created.descriptor, parent: parent.value, name: created.name)
        if !ABIAdapter.writeAll(data, to: staged.descriptor.value)
            || !ABIAdapter.synchronize(staged.descriptor.value) {
            throw PlatformError.write(path)
        }
        try validating()
        switch ABIAdapter.linkNewOutput(from: staged.name, to: name, in: parent.value) {
        case .installed:
            break
        case .present:
            throw PlatformError.outputExists(path)
        case .unavailable:
            throw PlatformError.write(path)
        }
        if !ABIAdapter.synchronize(parent.value) {
            throw PlatformError.outputDurabilityUnconfirmed(path)
        }
    }
}
