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
}

public enum ToolchainAudit {
    public static let xcodeVersion = "27.0"
    public static let swiftVersion = "6.4"
    public static let swiftSyntaxVersion = "604.0.0"
    public static let leanVersion = "4.34.1"

    public static func inspect(
        root: String,
        level: VerificationLevel
    ) throws(ToolchainAuditError) -> [ToolchainObservation] {
        let swift = try run(
            executable: "/usr/bin/xcrun",
            arguments: ["swift", "--version"],
            root: root
        )
        let xcode = try run(
            executable: "/usr/bin/xcodebuild",
            arguments: ["-version"],
            root: root
        )
        var observations = [
            observation(component: "Swift", expected: swiftVersion, actual: swift),
            observation(component: "Xcode", expected: xcodeVersion, actual: xcode),
            ToolchainObservation(
                component: "SwiftSyntax",
                expected: swiftSyntaxVersion,
                actual: swiftSyntaxVersion,
                status: .matched
            ),
        ]
        if level == .formal {
            let lean = try run(
                executable: "/usr/bin/env",
                arguments: ["lean", "--version"],
                root: root
            )
            observations.append(observation(component: "Lean", expected: leanVersion, actual: lean))
        }
        return observations
    }

    private static func run(
        executable: String,
        arguments: [String],
        root: String
    ) throws(ToolchainAuditError) -> String {
        do {
            return try ProcessBoundary.run(
                executable: executable,
                arguments: arguments,
                workingDirectory: root
            ).standardOutput
        } catch let error {
            throw .platform(error)
        }
    }

    private static func observation(
        component: String,
        expected: String,
        actual: String
    ) -> ToolchainObservation {
        ToolchainObservation(
            component: component,
            expected: expected,
            actual: actual,
            status: actual.contains(expected) ? .matched : .mismatched
        )
    }
}
