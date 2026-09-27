import Foundation
import SwiftestPlatform

public enum VerificationLevel: String, CaseIterable, Sendable {
    case swift
    case formal
}

public struct ToolchainObservation: Equatable, Sendable {
    public let component: String
    public let expected: String
    public let actual: String
    public let status: Observation

    public init(component: String, expected: String, actual: String, status: Observation) {
        self.component = component
        self.expected = expected
        self.actual = actual
        self.status = status
    }
}

public enum Observation: String, CaseIterable, Sendable {
    case matched
    case mismatched
}

public enum ToolchainAuditError: Error, Equatable, Sendable {
    case platform(PlatformError)
    case swiftSyntaxMetadata(String)
}

public enum ToolchainAudit {
    public static let xcodeVersion = "27.0"
    public static let swiftVersion = "6.4"
    public static let swiftSyntaxVersion = "604.0.0"
    public static let swiftSyntaxModuleVersion = "6.4.0.34.1"
    public static let leanVersion = PinnedLeanToolchain.version

    public static func inspect(
        root: String,
        level: VerificationLevel
    ) throws(ToolchainAuditError) -> [ToolchainObservation] {
        let scratch: ScratchDirectoryOwner
        do {
            scratch = try ScratchDirectoryOwner(
                parent: "/private/tmp",
                name: "swiftest-toolchain-" + String(PlatformClock.monotonicNanoseconds().rawValue)
            )
        } catch let error {
            throw .platform(error)
        }
        let swift = versionText(try runApple(
            executable: "/usr/bin/xcrun",
            arguments: ["swift", "--version"],
            root: root,
            scratch: scratch
        ))
        let xcode = versionText(try runApple(
            executable: "/usr/bin/xcodebuild",
            arguments: ["-version"],
            root: root,
            scratch: scratch
        ))
        let swiftSyntax = try hostSwiftSyntaxModuleVersion(
            root: root,
            swiftVersionOutput: swift,
            scratch: scratch
        )
        var observations = [
            observation(component: "Swift", expected: swiftVersion, actual: swift),
            observation(component: "Xcode", expected: xcodeVersion, actual: xcode),
            ToolchainObservation(
                component: "SwiftSyntax",
                expected: swiftSyntaxVersion + " / ABI " + swiftSyntaxModuleVersion,
                actual: swiftSyntax,
                status: swiftSyntax == swiftSyntaxModuleVersion ? .matched : .mismatched
            ),
        ]
        if level == .formal {
            let lean = try runLean(root: root, scratch: scratch)
            observations.append(observation(component: "Lean", expected: leanVersion, actual: lean))
        }
        return observations
    }

    private static func hostSwiftSyntaxModuleVersion(
        root: String,
        swiftVersionOutput: String,
        scratch: borrowing ScratchDirectoryOwner
    ) throws(ToolchainAuditError) -> String {
        let executable = try runApple(
            executable: "/usr/bin/xcrun",
            arguments: ["--find", "swift"],
            root: root,
            scratch: scratch
        ).standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if executable.isEmpty {
            throw .swiftSyntaxMetadata("swift-executable")
        }
        let architecture: String
        if swiftVersionOutput.contains("Target: arm64-") {
            architecture = "arm64"
        } else if swiftVersionOutput.contains("Target: x86_64-") {
            architecture = "x86_64"
        } else {
            throw .swiftSyntaxMetadata("host-architecture")
        }
        let toolchainUSR = URL(fileURLWithPath: executable)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let interface = toolchainUSR
            .appendingPathComponent("lib/swift/host/SwiftSyntax.swiftmodule")
            .appendingPathComponent(architecture + "-apple-macos.swiftinterface")
        let data: Data
        do {
            data = try FileSystemBoundary.read(path: interface.path)
        } catch let error {
            throw .platform(error)
        }
        guard let source = String(data: data, encoding: .utf8) else {
            throw .swiftSyntaxMetadata("invalid-utf8")
        }
        return try parseSwiftSyntaxModuleVersion(source)
    }

    static func parseSwiftSyntaxModuleVersion(_ interface: String) throws(ToolchainAuditError) -> String {
        guard let flags = interface.split(separator: "\n").first(where: {
            $0.hasPrefix("// swift-module-flags:")
        }),
            flags.contains("-module-name SwiftSyntax"),
            let marker = flags.range(of: "-user-module-version "),
            let version = flags[marker.upperBound...].split(separator: " ").first,
            !version.isEmpty else {
            throw .swiftSyntaxMetadata("missing-module-version")
        }
        return String(version)
    }

    private static func runApple(
        executable: String,
        arguments: [String],
        root: String,
        scratch: borrowing ScratchDirectoryOwner
    ) throws(ToolchainAuditError) -> ProcessOutput {
        do {
            return try ProcessBoundary.runPinnedApple(
                executable: executable,
                arguments: arguments,
                workingDirectory: root,
                scratch: scratch
            )
        } catch let error {
            throw .platform(error)
        }
    }

    private static func runLean(
        root: String,
        scratch: borrowing ScratchDirectoryOwner
    ) throws(ToolchainAuditError) -> String {
        do {
            let toolchain = try PinnedLeanToolchain.resolve()
            return versionText(try ProcessBoundary.runPinnedLean(
                toolchainBin: toolchain.bin,
                executable: toolchain.lean,
                arguments: ["--version"],
                workingDirectory: root,
                scratch: scratch
            ))
        } catch let error {
            throw .platform(error)
        }
    }

    static func versionText(_ output: ProcessOutput) -> String {
        output.standardOutput + "\n" + output.standardError
    }

    static func observation(
        component: String,
        expected: String,
        actual: String
    ) -> ToolchainObservation {
        ToolchainObservation(
            component: component,
            expected: expected,
            actual: actual,
            status: version(component: component, in: actual) == expected ? .matched : .mismatched
        )
    }

    private static func version(component: String, in output: String) -> String? {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        let candidates = lines.filter { line in
            switch component {
            case "Swift":
                return line.hasPrefix("Apple Swift version ")
                    || (line.hasPrefix("swift-driver version: ")
                        && line.contains(" Apple Swift version "))
            case "Xcode":
                return line.hasPrefix("Xcode ")
            case "Lean":
                return line.hasPrefix("Lean (version ")
            default:
                return false
            }
        }
        guard candidates.count == 1, let firstLine = candidates.first else {
            return nil
        }
        let suffix: Substring
        switch component {
        case "Swift":
            let swiftPrefix = "Apple Swift version "
            let driverPrefix = "swift-driver version: "
            if firstLine.hasPrefix(swiftPrefix) {
                suffix = firstLine.dropFirst(swiftPrefix.count)
            } else if firstLine.hasPrefix(driverPrefix) {
                let driver = firstLine.dropFirst(driverPrefix.count)
                guard let marker = driver.range(of: " Apple Swift version ") else {
                    return nil
                }
                let driverVersion = driver[..<marker.lowerBound]
                guard !driverVersion.isEmpty && !driverVersion.contains(" ") else {
                    return nil
                }
                suffix = driver[marker.upperBound...]
            } else {
                return nil
            }
        case "Xcode":
            let prefix = "Xcode "
            guard firstLine.hasPrefix(prefix) else {
                return nil
            }
            suffix = firstLine.dropFirst(prefix.count)
        case "Lean":
            let prefix = "Lean (version "
            guard firstLine.hasPrefix(prefix) else {
                return nil
            }
            suffix = firstLine.dropFirst(prefix.count)
        default:
            return nil
        }
        let candidate = suffix.prefix { character in
            character != " " && character != "," && character != ")"
        }
        if candidate.isEmpty {
            return nil
        }
        if component == "Xcode" && candidate.count != suffix.count {
            return nil
        }
        return String(candidate)
    }
}
