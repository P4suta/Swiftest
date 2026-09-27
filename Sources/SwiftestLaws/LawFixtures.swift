enum LawFixtureSwiftSource: String, Equatable, Sendable {
    case ordinary = "Sources/Fixture/Fixture.swift"
    case macroDeclaration = "Sources/SwiftestTesting/Macros.swift"
}

enum LawFixtureVerification: Equatable, Sendable {
    case swiftSource(path: LawFixtureSwiftSource)
    case specialized
}

public struct LawFixture: Equatable, Sendable {
    public let law: LawCode
    public let legal: String
    public let illegal: String
    let verification: LawFixtureVerification

    public init(law: LawCode, legal: String, illegal: String) {
        self.init(law: law, legal: legal, illegal: illegal, verification: .specialized)
    }

    fileprivate init(law: LawCode, legal: String, illegal: String, verification: LawFixtureVerification) {
        self.law = law
        self.legal = legal
        self.illegal = illegal
        self.verification = verification
    }

    fileprivate static func swiftSource(
        _ law: LawCode,
        legal: String,
        illegal: String,
        path: LawFixtureSwiftSource = .ordinary
    ) -> LawFixture {
        LawFixture(law: law, legal: legal, illegal: illegal, verification: .swiftSource(path: path))
    }

    fileprivate static func specialized(_ law: LawCode, legal: String, illegal: String) -> LawFixture {
        LawFixture(law: law, legal: legal, illegal: illegal, verification: .specialized)
    }
}

public enum LawFixtureCatalog {
    public static let all = LawCode.allCases.map(fixture(for:))

    private static func fixture(for law: LawCode) -> LawFixture {
        switch law {
        case .forbiddenComment:
            .swiftSource(law, legal: "let value = 1\n", illegal: "/" + "/ explanation\nlet value = 1\n")
        case .handwrittenDocumentation:
            .specialized(law, legal: "GeneratedSchema.json", illegal: "README.md")
        case .unreadableSource:
            .swiftSource(law, legal: "let value = 1\n", illegal: "let =\n")
        case .prohibitedTry:
            .swiftSource(law, legal: "let value = try operation()\n", illegal: "let value = try" + "? operation()\n")
        case .forceUnwrap:
            .swiftSource(law, legal: "guard let value else { return }\n", illegal: "let result = value" + "!\n")
        case .forceCast:
            .swiftSource(law, legal: "guard let value = input as? String else { return }\n", illegal: "let value = input as" + "! String\n")
        case .stringError:
            .swiftSource(law, legal: "throw Failure.invalid\n", illegal: "throw NSError(domain: \"failure\", code: 1)\n")
        case .ignoredResult:
            .swiftSource(law, legal: "let result = operation()\n", illegal: "_ " + "= operation()\n")
        case .semanticDefault:
            .swiftSource(law, legal: "guard let value else { throw Failure.missing }\n", illegal: "let result = value " + "?? fallback\n")
        case .optionalBoolean:
            .swiftSource(law, legal: "let state: State\n", illegal: "let state: Bool" + "?\n")
        case .policyBoolean:
            .swiftSource(law, legal: "func run(policy: Policy) {}\n", illegal: "func run(skip: Bool) {}\n")
        case .defaultClosedDomain:
            .swiftSource(law, legal: "switch value { case .one: break }\n", illegal: "@ClosedDomain enum Value { case one }\nswitch value { default: break }\n")
        case .handwrittenCases:
            .swiftSource(law, legal: "enum Value: CaseIterable { case one }\n", illegal: "enum Value { case one; static let allCases = [Value.one] }\n")
        case .forbiddenDependency:
            .specialized(law, legal: "import Foundation\n", illegal: "import ThirdParty\n")
        case .reverseDependency:
            .specialized(law, legal: "import SwiftestModel\n", illegal: "import SwiftestPresentation\n")
        case .testSupportImport:
            .specialized(law, legal: "import SwiftestModel\n", illegal: "import SwiftestModelTests\n")
        case .unreachableProduction:
            .specialized(law, legal: "SwiftestModel", illegal: "OrphanProduction")
        case .unclassifiedTarget:
            .specialized(law, legal: "Sources/SwiftestModel", illegal: "Sources/UnknownTarget")
        case .unclassifiedSource:
            .specialized(law, legal: "Sources/SwiftestModel/Model.swift", illegal: "report.json")
        case .uninspectedMacro:
            .swiftSource(
                law,
                legal: "@attached(body)\npublic macro WorldTest(worlds: WorldSpace, body: @escaping @Sendable (World) async throws -> Void) = #externalMacro(module: \"SwiftestMacros\", type: \"WorldTestMacro\")",
                illegal: "@attached(body)\npublic macro WorldTest(worlds: WorldSpace, body: @escaping @Sendable (World) async throws -> Void) = #externalMacro(module: \"TestingMacros\", type: \"TestDeclarationMacro\")",
                path: .macroDeclaration
            )
        case .rawProcess:
            .swiftSource(law, legal: "ProcessBoundary.run()\n", illegal: "Process()\n")
        case .detachedTask:
            .swiftSource(law, legal: "TaskBoundary.yield()\n", illegal: "Task.detached {}\n")
        case .globalMutableState:
            .swiftSource(law, legal: "enum Globals { static let state = State() }\n", illegal: "enum Globals { static var state = State() }\n")
        case .ownedExistential:
            .swiftSource(law, legal: "func use<T: Service>(_ value: T) {}\n", illegal: "let service: any Service\n")
        case .anyType:
            .swiftSource(law, legal: "let value: Value\n", illegal: "let value: Any\n")
        case .mirror:
            .swiftSource(law, legal: "Metadata.inspect(value)\n", illegal: "Mirror(reflecting: value)\n")
        case .uncheckedArithmetic:
            .swiftSource(law, legal: "let result = value.addingReportingOverflow(1)\n", illegal: "let result = value " + "&+ 1\n")
        case .directEnvironment:
            .swiftSource(law, legal: "EnvironmentBoundary.value(for: \"KEY\")\n", illegal: "ProcessInfo.processInfo.environment[\"KEY\"]\n")
        case .directClock:
            .swiftSource(law, legal: "PlatformClock.monotonicNanoseconds()\n", illegal: "let clock = ContinuousClock()\n")
        case .directRandomness:
            .swiftSource(law, legal: "DeterministicRandom(seed: 1)\n", illegal: "Int.random(in: 0...1)\n")
        case .directFileWrite:
            .swiftSource(law, legal: "FileSystemBoundary.write(data)\n", illegal: "try data.write(to: url)\n")
        case .unsafeOutsideBoundary:
            .swiftSource(law, legal: "ABIAdapter.copy(bytes)\n", illegal: "withUnsafeBytes(of: value) { body($0) }\n")
        case .vnodeEventProtocol:
            .specialized(
                law,
                legal: "enum ABIAdapter { private static func makeVnodeRegistration(descriptor: Int32, mutationFlags: UInt32) -> Darwin.kevent64_s { Darwin.kevent64_s(ident: UInt64(descriptor), filter: Int16(EVFILT_VNODE), flags: UInt16(EV_ADD | EV_ENABLE | EV_CLEAR), fflags: mutationFlags, data: 0, udata: 0, ext: (0, 0)) } }\n",
                illegal: "enum ABIAdapter { private static func makeVnodeRegistration(descriptor: Int32, mutationFlags: UInt32) -> Darwin.kevent64_s { Darwin.kevent64_s(ident: UInt64(descriptor), filter: Int16(EVFILT_VNODE), flags: UInt16(EV_ADD | EV_ENABLE), fflags: mutationFlags, data: 0, udata: 0, ext: (0, 0)) } }\n"
            )
        case .catalogSerialization:
            .specialized(
                law,
                legal: "enum ReportCodec { private static func catalogValue(_ catalog: EvidenceCatalog) -> JSONValue { return .object([\"run\": .string(catalog.run.rawValue)]) } }\n",
                illegal: "enum ReportCodec { private static func catalogValue(_ catalog: EvidenceCatalog) -> JSONValue { return .object([:]) } }\n"
            )
        case .eventGenerationWitness:
            .specialized(law, legal: "health.recordAttributeEvent(at: path)", illegal: "health.snapshot")
        case .faultObservationProvenance:
            .specialized(
                law,
                legal: "func run() { let process = SwiftPackageTargetObserver.denialReceipt(.processDenied); let evidence = SwiftPackageTargetObserver.denialReceipt(.evidence); return denialReceipt.close(activation: activation, observedOutcome: outcome) }\n",
                illegal: "func run() { return .handled([FaultActivationObservation(point: point, result: .failedClosed)]) }\n"
            )
        case .toolchainMismatch:
            .specialized(law, legal: "Apple Swift version 6.4", illegal: "Apple Swift version 6.3")
        case .missingExternalProof:
            .specialized(law, legal: "Lean version 4.34.1", illegal: "Lean unavailable")
        }
    }

    public static let claimDefinitionEncoding = LawFixture.specialized(
        .catalogSerialization,
        legal: "enum ReportCodec { private static func catalogValue(_ catalog: EvidenceCatalog) -> JSONValue { return .object([\"preservationClaims\": .array(catalog.preservationClaims.definitions.map { claim in .object([\"id\": .string(claim.id.rawValue), \"name\": .string(claim.name)]) })]) } }\n",
        illegal: "enum ReportCodec { private static func catalogValue(_ catalog: EvidenceCatalog) -> JSONValue { return .object([\"preservationClaims\": .array(catalog.preservationClaims.definitions.map { claim in .object([\"id\": .string(claim.id.rawValue)]) })]) } }\n"
    )
}
