public struct LawFixture: Equatable, Sendable {
    public let law: LawCode
    public let legal: String
    public let illegal: String

    public init(law: LawCode, legal: String, illegal: String) {
        self.law = law
        self.legal = legal
        self.illegal = illegal
    }
}

public enum LawFixtureCatalog {
    public static let all: [LawFixture] = [
        LawFixture(
            law: .forbiddenComment,
            legal: "let value = 1\n",
            illegal: "/" + "/ explanation\nlet value = 1\n"
        ),
        LawFixture(
            law: .handwrittenDocumentation,
            legal: "GeneratedSchema.json",
            illegal: "README.md"
        ),
        LawFixture(
            law: .unreadableSource,
            legal: "let value = 1\n",
            illegal: "let =\n"
        ),
        LawFixture(
            law: .prohibitedTry,
            legal: "let value = try operation()\n",
            illegal: "let value = try" + "? operation()\n"
        ),
        LawFixture(
            law: .forceUnwrap,
            legal: "guard let value else { return }\n",
            illegal: "let result = value" + "!\n"
        ),
        LawFixture(
            law: .forceCast,
            legal: "guard let value = input as? String else { return }\n",
            illegal: "let value = input as" + "! String\n"
        ),
        LawFixture(
            law: .stringError,
            legal: "throw Failure.invalid\n",
            illegal: "throw NSError(domain: \"failure\", code: 1)\n"
        ),
        LawFixture(
            law: .ignoredResult,
            legal: "let result = operation()\n",
            illegal: "_ " + "= operation()\n"
        ),
        LawFixture(
            law: .semanticDefault,
            legal: "guard let value else { throw Failure.missing }\n",
            illegal: "let result = value " + "?? fallback\n"
        ),
        LawFixture(
            law: .optionalBoolean,
            legal: "let state: State\n",
            illegal: "let state: Bool" + "?\n"
        ),
        LawFixture(
            law: .policyBoolean,
            legal: "func run(policy: Policy) {}\n",
            illegal: "func run(skip: Bool) {}\n"
        ),
        LawFixture(
            law: .defaultClosedDomain,
            legal: "switch value { case .one: break }\n",
            illegal: "@ClosedDomain enum Value { case one }\nswitch value { default: break }\n"
        ),
        LawFixture(
            law: .handwrittenCases,
            legal: "enum Value: CaseIterable { case one }\n",
            illegal: "enum Value { case one; static let allCases = [Value.one] }\n"
        ),
        LawFixture(
            law: .forbiddenDependency,
            legal: "import Foundation\n",
            illegal: "import ThirdParty\n"
        ),
        LawFixture(
            law: .reverseDependency,
            legal: "import SwiftestModel\n",
            illegal: "import SwiftestPresentation\n"
        ),
        LawFixture(
            law: .testSupportImport,
            legal: "import SwiftestModel\n",
            illegal: "import SwiftestModelTests\n"
        ),
        LawFixture(
            law: .unreachableProduction,
            legal: "SwiftestModel",
            illegal: "OrphanProduction"
        ),
        LawFixture(
            law: .unclassifiedTarget,
            legal: "Sources/SwiftestModel",
            illegal: "Sources/UnknownTarget"
        ),
        LawFixture(
            law: .uninspectedMacro,
            legal: "#externalMacro(module: \"TestingMacros\", type: \"ExpectMacro\")",
            illegal: "#externalMacro(module: \"UnknownMacros\", type: \"UnknownMacro\")"
        ),
        LawFixture(
            law: .rawProcess,
            legal: "ProcessBoundary.run()\n",
            illegal: "Process()\n"
        ),
        LawFixture(
            law: .detachedTask,
            legal: "TaskBoundary.yield()\n",
            illegal: "Task.detached {}\n"
        ),
        LawFixture(
            law: .globalMutableState,
            legal: "let state = State()\n",
            illegal: "var state = State()\n"
        ),
        LawFixture(
            law: .ownedExistential,
            legal: "func use<T: Service>(_ value: T) {}\n",
            illegal: "let service: any Service\n"
        ),
        LawFixture(
            law: .anyType,
            legal: "let value: Value\n",
            illegal: "let value: Any\n"
        ),
        LawFixture(
            law: .mirror,
            legal: "Metadata.inspect(value)\n",
            illegal: "Mirror(reflecting: value)\n"
        ),
        LawFixture(
            law: .uncheckedArithmetic,
            legal: "let result = value.addingReportingOverflow(1)\n",
            illegal: "let result = value " + "&+ 1\n"
        ),
        LawFixture(
            law: .directEnvironment,
            legal: "EnvironmentBoundary.value(for: \"KEY\")\n",
            illegal: "ProcessInfo.processInfo.environment[\"KEY\"]\n"
        ),
        LawFixture(
            law: .directClock,
            legal: "PlatformClock.monotonicNanoseconds()\n",
            illegal: "let clock = ContinuousClock()\n"
        ),
        LawFixture(
            law: .directRandomness,
            legal: "DeterministicRandom(seed: 1)\n",
            illegal: "Int.random(in: 0...1)\n"
        ),
        LawFixture(
            law: .directFileWrite,
            legal: "FileSystemBoundary.write(data)\n",
            illegal: "try data.write(to: url)\n"
        ),
        LawFixture(
            law: .unsafeOutsideBoundary,
            legal: "ABIAdapter.copy(bytes)\n",
            illegal: "withUnsafeBytes(of: value) { body($0) }\n"
        ),
        LawFixture(
            law: .toolchainMismatch,
            legal: "Apple Swift version 6.4",
            illegal: "Apple Swift version 6.3"
        ),
        LawFixture(
            law: .missingExternalProof,
            legal: "Lean version 4.34.1",
            illegal: "Lean unavailable"
        ),
    ]
}
