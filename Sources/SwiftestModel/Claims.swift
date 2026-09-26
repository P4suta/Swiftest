public enum Preservation: Sendable {}

public enum Detection: Sendable {}

public enum Environment: Sendable {}

public enum Defect: Sendable {}

public enum ClaimConstructionError: Error, Equatable, Sendable {
    case emptyName
}

public struct Claim<Polarity>: Hashable, Sendable {
    public let id: ClaimID
    public let name: String

    private init(id: ClaimID, name: String) {
        self.id = id
        self.name = name
    }
}

extension Claim where Polarity == Preservation {
    public static func preservation(
        id: ClaimID,
        name: String
    ) throws(ClaimConstructionError) -> Claim<Preservation> {
        if name.isEmpty {
            throw .emptyName
        }
        return Claim<Preservation>(id: id, name: name)
    }
}

extension Claim where Polarity == Detection {
    public static func detection(
        id: ClaimID,
        name: String
    ) throws(ClaimConstructionError) -> Claim<Detection> {
        if name.isEmpty {
            throw .emptyName
        }
        return Claim<Detection>(id: id, name: name)
    }
}

public struct Perturbation<Kind>: Hashable, Sendable {
    public let code: String

    private init(code: String) {
        self.code = code
    }
}

extension Perturbation where Kind == Environment {
    public static func environment(_ code: String) throws(IdentifierError) -> Perturbation<Environment> {
        try validatePerturbationCode(code)
        return Perturbation<Environment>(code: code)
    }
}

extension Perturbation where Kind == Defect {
    public static func defect(_ code: String) throws(IdentifierError) -> Perturbation<Defect> {
        try validatePerturbationCode(code)
        return Perturbation<Defect>(code: code)
    }
}

private func validatePerturbationCode(_ code: String) throws(IdentifierError) {
    if code.isEmpty {
        throw .empty
    }
    if code.utf8.count > 128 {
        throw .tooLong
    }
    for (index, byte) in code.utf8.enumerated() {
        let allowed =
            (byte >= 48 && byte <= 57)
            || (byte >= 65 && byte <= 90)
            || (byte >= 97 && byte <= 122)
            || byte == 45
            || byte == 46
            || byte == 58
            || byte == 95
        if !allowed {
            throw .invalidCharacter(index)
        }
    }
}

public enum DiagnosticCode: String, CaseIterable, Sendable {
    case baselineFailed = "baseline-failed"
    case mutationSurvived = "mutation-survived"
    case mutationUnreached = "mutation-unreached"
    case mutationUninfected = "mutation-uninfected"
    case compilerRejected = "compiler-rejected"
    case apparatusFailed = "apparatus-failed"
    case invalidWire = "invalid-wire"
    case invalidState = "invalid-state"
    case missingEvidence = "missing-evidence"
    case lawViolated = "law-violated"
    case reviewMissing = "review-missing"
}

public struct Diagnostic: Hashable, Sendable {
    public let code: DiagnosticCode
    public let subject: String
    public let detail: String

    public init(code: DiagnosticCode, subject: String, detail: String) {
        self.code = code
        self.subject = subject
        self.detail = detail
    }
}

public enum CleanFailure: Error, Equatable, Sendable {
    case preservationViolation(ClaimID, WorldID)
    case baselineTestFailed(TestID, WorldID)
    case baselineCrashed(TestID, WorldID)
}

public enum MutantFailure: Error, Equatable, Sendable {
    case survived(MutantID, ClaimID)
    case notReached(MutantID)
    case notInfected(MutantID)
    case compilerRejected(MutantID)
    case equivalentWithoutProof(MutantID)
}

public enum ApparatusFailure: Error, Equatable, Sendable {
    case process(Diagnostic)
    case codec(Diagnostic)
    case store(Diagnostic)
    case toolchain(Diagnostic)
    case resourceOwnership(Diagnostic)
    case incompleteCatalog(Diagnostic)
}

public enum ExecutionFailure: Error, Equatable, Sendable {
    case clean(CleanFailure)
    case mutant(MutantFailure)
    case apparatus(ApparatusFailure)

    public var diagnostic: Diagnostic {
        switch self {
        case .clean(.preservationViolation(let claim, let world)):
            Diagnostic(code: .baselineFailed, subject: claim.rawValue + ":" + world.rawValue, detail: "preservation violated")
        case .clean(.baselineTestFailed(let test, let world)):
            Diagnostic(code: .baselineFailed, subject: test.rawValue + ":" + world.rawValue, detail: "baseline test failed")
        case .clean(.baselineCrashed(let test, let world)):
            Diagnostic(code: .baselineFailed, subject: test.rawValue + ":" + world.rawValue, detail: "baseline crashed")
        case .mutant(.survived(let mutant, let claim)):
            Diagnostic(code: .mutationSurvived, subject: mutant.rawValue + ":" + claim.rawValue, detail: "mutant survived")
        case .mutant(.notReached(let mutant)):
            Diagnostic(code: .mutationUnreached, subject: mutant.rawValue, detail: "mutant was not reached")
        case .mutant(.notInfected(let mutant)):
            Diagnostic(code: .mutationUninfected, subject: mutant.rawValue, detail: "mutant did not infect behavior")
        case .mutant(.compilerRejected(let mutant)):
            Diagnostic(code: .compilerRejected, subject: mutant.rawValue, detail: "compiler rejected mutant")
        case .mutant(.equivalentWithoutProof(let mutant)):
            Diagnostic(code: .missingEvidence, subject: mutant.rawValue, detail: "equivalence proof absent")
        case .apparatus(.process(let diagnostic)),
             .apparatus(.codec(let diagnostic)),
             .apparatus(.store(let diagnostic)),
             .apparatus(.toolchain(let diagnostic)),
             .apparatus(.resourceOwnership(let diagnostic)),
             .apparatus(.incompleteCatalog(let diagnostic)):
            diagnostic
        }
    }
}

public enum ObservationStatus: String, CaseIterable, Sendable {
    case passed
    case failed
    case provenIrrelevant = "proven-irrelevant"
}

public struct ClaimObservation: Equatable, Sendable {
    public let claim: ClaimID
    public let world: WorldID
    public let status: ObservationStatus
    public let diagnostic: Diagnostic?

    public init(
        claim: ClaimID,
        world: WorldID,
        status: ObservationStatus,
        diagnostic: Diagnostic?
    ) {
        self.claim = claim
        self.world = world
        self.status = status
        self.diagnostic = diagnostic
    }
}
