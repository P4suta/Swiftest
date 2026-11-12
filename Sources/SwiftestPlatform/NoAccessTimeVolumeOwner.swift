import Foundation
import SwiftestModel

public enum VolumeAccessTimeUpdates: Equatable, Sendable {
    case enabled
    case disabled
}

struct VolumeMountMetadata: Equatable, Sendable {
    let mountPoint: String
    let accessTimeUpdates: VolumeAccessTimeUpdates
}

public struct NoAccessTimeVolumeOwner: ~Copyable {
    private let scratch: ScratchDirectoryOwner
    private let identity: CanonicalDirectoryIdentity
    private let root: String

    private static let control = ProcessRunControl(
        maximumDuration: .measured(60_000_000_000),
        cancellation: { .active }
    )

    public init() throws(PlatformError) {
        let probe = try ProcessBoundary.run(
            executable: "/usr/sbin/diskutil",
            arguments: ["image", "create", "blank", "--help"],
            workingDirectory: nil,
            control: Self.control
        )
        guard probe.exitCode == 0 else {
            throw .unsupportedPlatform("proof-volume")
        }
        let scratch = try ScratchDirectoryOwner(
            parent: "/private/tmp",
            name: "swiftest-proof-volume-" + String(PlatformClock.monotonicNanoseconds().rawValue)
        )
        let image = scratch.path + "/proofs.sparsebundle"
        let root = scratch.path + "/volume"
        let identity: CanonicalDirectoryIdentity
        do throws(PlatformError) {
            try Self.requireTool("/usr/sbin/diskutil", [
                "image", "create", "blank", "--size", "1073741824", "--format", "UDSB",
                "--fs", "APFS", "--volumeName", "SwiftestProofs", image,
            ])
            try Self.requireTool("/usr/sbin/diskutil", [
                "image", "attach", "--nobrowse", "--mountOptions", "noatime",
                "--mountPoint", root, "--mp", "forceMount", image,
            ])
            identity = try Self.verifiedRoot(root)
        } catch let failure {
            do {
                try Self.detachIfMounted(root)
            } catch {
                ABIAdapter.terminateFailure("swiftest: proof volume cleanup failed\n")
            }
            throw failure
        }
        self.scratch = scratch
        self.identity = identity
        self.root = root
    }

    public borrowing func withRoot<Result, Failure: Error>(
        _ operation: (String) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        try operation(root)
    }

    static func verifiedRoot(_ root: String) throws(PlatformError) -> CanonicalDirectoryIdentity {
        let identity = try CanonicalPathBoundary.captureDirectoryIdentity(root)
        guard identity.canonicalPath == root,
            let mount = ABIAdapter.volumeMountMetadata(at: root),
            mount.mountPoint == root, mount.accessTimeUpdates == .disabled else {
            throw .invalidRoot(root)
        }
        return identity
    }

    private static func requireTool(_ executable: String, _ arguments: [String]) throws(PlatformError) {
        let result = try ProcessBoundary.run(
            executable: executable,
            arguments: arguments,
            workingDirectory: nil,
            control: control
        )
        guard result.exitCode == 0 else {
            throw .processExit(executable, result.exitCode, result.failureDetail)
        }
    }

    private static func detachIfMounted(_ root: String) throws(PlatformError) {
        switch ABIAdapter.directoryPresence(at: root) {
        case .absent:
            return
        case .unavailable:
            throw .invalidRoot(root)
        case .present:
            guard let mount = ABIAdapter.volumeMountMetadata(at: root) else {
                throw .invalidRoot(root)
            }
            if mount.mountPoint == root {
                try requireTool("/usr/sbin/diskutil", ["eject", root])
            }
        }
    }

    deinit {
        do {
            try scratch.verifyOwnership()
            try identity.verifyCurrentLocation()
            guard ABIAdapter.volumeMountMetadata(at: root)?.mountPoint == root else {
                throw PlatformError.invalidRoot(root)
            }
            try Self.requireTool("/usr/sbin/diskutil", ["eject", root])
        } catch {
            ABIAdapter.terminateFailure("swiftest: proof volume cleanup failed\n")
        }
    }
}
