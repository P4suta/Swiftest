import SwiftestModel

public enum LawCode: String, CaseIterable, Hashable, Sendable {
    case forbiddenComment = "comment.forbidden"
    case handwrittenDocumentation = "documentation.handwritten"
    case unreadableSource = "source.unreadable"
    case prohibitedTry = "failure.optional-or-forced-try"
    case forceUnwrap = "failure.force-unwrap"
    case forceCast = "failure.force-cast"
    case stringError = "failure.string-error"
    case ignoredResult = "result.ignored"
    case semanticDefault = "value.semantic-default"
    case optionalBoolean = "value.optional-boolean"
    case policyBoolean = "policy.boolean"
    case defaultClosedDomain = "domain.default-arm"
    case handwrittenCases = "domain.handwritten-cases"
    case forbiddenDependency = "dependency.forbidden"
    case reverseDependency = "dependency.reverse"
    case testSupportImport = "dependency.test-support"
    case unreachableProduction = "production.test-only"
    case unclassifiedTarget = "target.unclassified"
    case unclassifiedSource = "source.unclassified"
    case uninspectedMacro = "macro.uninspected"
    case rawProcess = "adapter.raw-process"
    case detachedTask = "adapter.detached-task"
    case globalMutableState = "state.global-mutable"
    case ownedExistential = "type.owned-existential"
    case anyType = "type.any"
    case mirror = "type.mirror"
    case uncheckedArithmetic = "arithmetic.unchecked"
    case directEnvironment = "adapter.environment"
    case directClock = "adapter.clock"
    case directRandomness = "adapter.randomness"
    case directFileWrite = "adapter.file-write"
    case unsafeOutsideBoundary = "unsafe.outside-boundary"
    case toolchainMismatch = "toolchain.mismatch"
    case missingExternalProof = "proof.external-missing"
}

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
