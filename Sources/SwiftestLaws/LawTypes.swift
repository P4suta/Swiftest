import SwiftestModel

public typealias LawCode = SwiftestModel.LawCode

public enum RequiredDirective: String, CaseIterable, Sendable {
    case swiftToolsVersion = "swift-tools-version"
    case shellShebang = "shell-shebang"
    case spdxApache2 = "spdx-apache-2.0"
    case spdxMIT = "spdx-mit"
}

public enum AuditedBoundary: String, CaseIterable, Sendable {
    case platformABI = "SwiftestPlatform/ABIAdapter.swift"
    case platformCapabilities = "SwiftestPlatform/Capabilities.swift"
    case platformProcess = "SwiftestPlatform/ProcessBoundary.swift"
    case testingStableABI = "SwiftestTesting/Macros.swift"
}

public struct SourceLocation: Hashable, Sendable {
    public let file: String
    public let line: Int
    public let column: Int

    public init(file: String, line: Int, column: Int) {
        self.file = file
        self.line = line
        self.column = column
    }
}

public struct LawViolation: Hashable, Sendable {
    public let law: LawCode
    public let location: SourceLocation
    public let subject: String

    public init(law: LawCode, location: SourceLocation, subject: String) {
        self.law = law
        self.location = location
        self.subject = subject
    }
}

public struct LawReport: Equatable, Sendable {
    public let checkedFiles: EvidenceCount
    public let violations: [LawViolation]

    public init(checkedFiles: EvidenceCount, violations: [LawViolation]) {
        self.checkedFiles = checkedFiles
        self.violations = violations
    }

    public var passed: Bool {
        violations.isEmpty
    }
}

public enum LawScannerError: Error, Equatable, Sendable {
    case platform(String)
    case count(NumericValueError)
    case invalidRoot(String)
}
