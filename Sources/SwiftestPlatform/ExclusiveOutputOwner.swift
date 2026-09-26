import Foundation

private struct OwnedDescriptor: ~Copyable {
    let value: Int32

    deinit {
        ABIAdapter.closeOrTerminate(value)
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
        let descriptor: Int32
        switch ABIAdapter.openNewOutput(named: name, in: parent.value) {
        case .created(let value):
            descriptor = value
        case .present:
            throw .outputExists(path)
        case .unavailable:
            throw .write(path)
        }
        let file = OwnedDescriptor(value: descriptor)
        if !ABIAdapter.writeAll(data, to: file.value) || !ABIAdapter.synchronize(file.value) {
            throw .write(path)
        }
    }
}
