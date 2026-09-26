import Foundation
import Swiftest
import SwiftestCodec
import SwiftestLaws
import SwiftestPlatform
import SwiftestReport
import SwiftestStore

enum CLICommand: String, CaseIterable {
    case verify
    case watch
    case explain
    case replay
    case review
    case doctor
    case shard
    case merge
    case snapshot
    case migrate
    case fix
    case laws
}

struct CommandDescriptor {
    let command: CLICommand
    let summary: String

    static let all: [CommandDescriptor] = [
        CommandDescriptor(command: .verify, summary: "close evidence and emit a report"),
        CommandDescriptor(command: .watch, summary: "verify the current source state"),
        CommandDescriptor(command: .explain, summary: "derive help, verdicts, or schema"),
        CommandDescriptor(command: .replay, summary: "strictly replay a recorded report"),
        CommandDescriptor(command: .review, summary: "perform independent report review"),
        CommandDescriptor(command: .doctor, summary: "audit pinned toolchains"),
        CommandDescriptor(command: .shard, summary: "partition a complete ordinal domain"),
        CommandDescriptor(command: .merge, summary: "merge reviewed report envelopes"),
        CommandDescriptor(command: .snapshot, summary: "verify or explicitly record a snapshot"),
        CommandDescriptor(command: .migrate, summary: "strictly migrate canonical wire data"),
        CommandDescriptor(command: .fix, summary: "emit mechanically actionable law locations"),
        CommandDescriptor(command: .laws, summary: "enforce all repository laws"),
    ]
}

enum CLIError: Error {
    case usage(String)
    case laws(Int)
    case unassured(Verdict)
    case unverifiableReport(Digest)
    case toolchain(String)
    case formal(String)
    case report(ReportError)
    case audit(AuditError)
    case digest(DigestError)
    case identifier(IdentifierError)
    case number(NumericValueError)
    case platform(PlatformError)
    case path(ArtifactPathError)
    case codec(StrictJSONError)
    case snapshot(SnapshotError)
    case faultDeclaration(FaultDeclarationError)
    case faultAudit(FaultAuditError)
    case outputInsideRepository(String)
    case outputExists(String)
}

@main
struct SwiftestCommand {
    static func main() {
        do {
            try run()
        } catch {
            ProcessExitBoundary.fail(String(describing: error))
        }
    }

    static func run() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.isEmpty || arguments == ["--help"] || arguments == ["-h"] {
            print(help(), terminator: "")
            return
        }
        guard let command = CLICommand(rawValue: arguments[0]) else {
            throw CLIError.usage(arguments[0])
        }
        let rest = Array(arguments.dropFirst())
        switch command {
        case .verify:
            try verify(rest)
        case .watch:
            try verify(rest)
        case .explain:
            try explain(rest)
        case .replay:
            try replay(rest)
        case .review:
            try review(rest)
        case .doctor:
            try doctor(rest)
        case .shard:
            try shard(rest)
        case .merge:
            try merge(rest)
        case .snapshot:
            try snapshot(rest)
        case .migrate:
            try migrate(rest)
        case .fix:
            try fix(rest)
        case .laws:
            try laws(rest)
        }
    }

    static func help() -> String {
        let commands = CommandDescriptor.all.map {
            "  " + $0.command.rawValue + "\t" + $0.summary
        }.joined(separator: "\n")
        return "swiftest <command> [arguments]\n\n" + commands + "\n"
    }

    static func root(from arguments: [String]) -> String {
        for argument in arguments where !argument.hasPrefix("--") {
            return argument
        }
        return WorkingDirectoryBoundary.current()
    }

    static func laws(_ arguments: [String]) throws {
        let repository = root(from: arguments)
        let report = try LawScanner.scan(root: repository)
        try emitViolations(report)
        let level: VerificationLevel = arguments.contains("--formal") ? .formal : .swift
        let observations: [ToolchainObservation]
        do {
            observations = try ToolchainAudit.inspect(root: repository, level: level)
        } catch let error {
            throw CLIError.toolchain(String(describing: error))
        }
        for observation in observations where observation.status == .mismatched {
            throw CLIError.toolchain(observation.component + ":" + observation.actual)
        }
        if level == .formal {
            do {
                try FormalVerification.verifyOracle(
                    root: repository,
                    swiftOracle: VerdictOracle.text() + FaultOracle.text() + ReportVerdictOracle.text()
                        + ArtifactPathOracle.text()
                )
            } catch let error {
                throw CLIError.formal(String(describing: error))
            }
        }
        print("laws=passed files=" + String(report.checkedFiles.rawValue))
    }

    static func verify(_ arguments: [String]) throws {
        let options = try VerifyOptions.parse(arguments)
        let repositoryIdentity: CanonicalDirectoryIdentity
        do {
            repositoryIdentity = try CanonicalPathBoundary.captureDirectoryIdentity(options.root)
        } catch let error {
            throw CLIError.platform(error)
        }
        let repository = repositoryIdentity.canonicalPath
        let outputOwner: ExclusiveOutputOwner?
        if let output = options.output {
            outputOwner = try validateReportOutput(output, repository: repository)
        } else {
            outputOwner = nil
        }
        let initialSeal: Result<SourceTreeSeal, SourceTreeSealError>
        do {
            initialSeal = .success(try SourceTreeSeal.capture(root: repository))
        } catch let error {
            initialSeal = .failure(error)
        }
        let lawReport = try LawScanner.scan(root: repository)
        let tests: TargetTestObservation
        let sourceDigest: Digest?
        do {
            try repositoryIdentity.verifyCurrentLocation()
            let seal = try initialSeal.get()
            try seal.verifyUnchanged()
            try repositoryIdentity.verifyCurrentLocation()
            let observed: TargetTestObservation
            switch options.target {
            case .automatic:
                let package = SwiftPackageTestDriver.observe(root: repository)
                if case .notConfigured = package {
                    observed = XcodeTargetTestDriver.unconfiguredProject(root: repository)
                } else {
                    observed = package
                }
            case .xcode(let scheme, let destination, let project, let workspace):
                observed = XcodeTargetTestDriver.observe(
                    root: repository,
                    scheme: scheme,
                    destination: destination,
                    project: project,
                    workspace: workspace
                )
            }
            try repositoryIdentity.verifyCurrentLocation()
            try seal.verifyUnchanged()
            try repositoryIdentity.verifyCurrentLocation()
            sourceDigest = try seal.manifestDigest()
            tests = observed
        } catch {
            sourceDigest = nil
            tests = .apparatus(Diagnostic(
                code: .apparatusFailed,
                subject: "source-integrity",
                detail: "source or project changed during test execution"
            ))
        }
        let report = try makeReport(lawReport, tests: tests, sourceDigest: sourceDigest)
        let data: Data
        do {
            data = try ReportCodec.encode(report)
        } catch let error {
            throw CLIError.report(error)
        }
        do {
            try repositoryIdentity.verifyCurrentLocation()
        } catch let error {
            throw CLIError.platform(error)
        }
        if let outputOwner {
            do {
                try outputOwner.write(data)
            } catch let error {
                throw outputError(error)
            }
        } else {
            guard let text = String(data: data, encoding: .utf8) else {
                throw CLIError.usage("report-encoding")
            }
            print(text)
        }
        if report.verdict == .invalid {
            throw CLIError.unassured(.invalid)
        }
        if !lawReport.passed {
            throw CLIError.laws(lawReport.violations.count)
        }
        if case .requireAssurance = options.gapPolicy {
            switch report.verdict {
            case .assured, .changeAssured, .scopeAssured:
                break
            case .unsettled, .gaps, .gapsAndUnsettled, .invalid:
                throw CLIError.unassured(report.verdict)
            }
        }
    }

    static func explain(_ arguments: [String]) throws {
        guard let subject = arguments.first else {
            throw CLIError.usage("explain")
        }
        switch subject {
        case "schema":
            print(StrictJSON.render(ReportCodec.schema()))
        case "verdicts":
            for verdict in Verdict.allCases {
                print(verdict.rawValue)
            }
        case "commands":
            print(help(), terminator: "")
        default:
            throw CLIError.usage(subject)
        }
    }

    static func replay(_ arguments: [String]) throws {
        guard arguments.count == 1 else {
            throw CLIError.usage("replay")
        }
        let envelope = try readEnvelope(arguments[0])
        print("replay=unverified claimed=" + envelope.verdict.rawValue + " run=" + envelope.run.rawValue)
        throw CLIError.unverifiableReport(envelope.catalogDigest)
    }

    static func review(_ arguments: [String]) throws {
        if arguments == ["--verdict-oracle"] {
            print(VerdictOracle.text(), terminator: "")
            return
        }
        if arguments == ["--formal-oracle"] {
            print(
                VerdictOracle.text() + FaultOracle.text() + ReportVerdictOracle.text()
                    + ArtifactPathOracle.text(),
                terminator: ""
            )
            return
        }
        guard arguments.count == 1 else {
            throw CLIError.usage("review")
        }
        let envelope = try readEnvelope(arguments[0])
        print("review=unverified digest=" + envelope.catalogDigest.rawValue)
        throw CLIError.unverifiableReport(envelope.catalogDigest)
    }

    static func doctor(_ arguments: [String]) throws {
        let repository = root(from: arguments)
        let level: VerificationLevel = arguments.contains("--formal") ? .formal : .swift
        let observations: [ToolchainObservation]
        do {
            observations = try ToolchainAudit.inspect(root: repository, level: level)
        } catch let error {
            throw CLIError.toolchain(String(describing: error))
        }
        for observation in observations {
            print(
                observation.component
                    + " expected=" + observation.expected
                    + " status=" + observation.status.rawValue
            )
        }
        if observations.contains(where: { $0.status == .mismatched }) {
            throw CLIError.toolchain("mismatch")
        }
    }

    static func shard(_ arguments: [String]) throws {
        guard arguments.count == 3,
            let count = Int(arguments[0]),
            let index = Int(arguments[1]),
            let items = Int(arguments[2]),
            count > 0,
            index >= 0,
            index < count,
            items >= 0 else {
            throw CLIError.usage("shard")
        }
        var values: [String] = []
        for item in 0..<items where item % count == index {
            values.append(String(item))
        }
        print(values.joined(separator: "\n"))
    }

    static func merge(_ arguments: [String]) throws {
        if arguments.isEmpty {
            throw CLIError.usage("merge")
        }
        let envelopes = try arguments.map(readEnvelope)
        guard let first = envelopes.first else {
            throw CLIError.usage("merge")
        }
        print("merge=unverified parts=" + String(envelopes.count))
        throw CLIError.unverifiableReport(first.catalogDigest)
    }

    static func snapshot(_ arguments: [String]) throws {
        guard arguments.count == 4 else {
            throw CLIError.usage("snapshot")
        }
        let action = arguments[0]
        let root = arguments[1]
        let path: ArtifactPath
        do {
            path = try .parse(arguments[2])
        } catch let error {
            throw CLIError.path(error)
        }
        let value: Data
        do {
            value = try FileSystemBoundary.read(path: arguments[3])
        } catch let error {
            throw CLIError.platform(error)
        }
        if action == "verify" {
            do {
                try SnapshotEngine.verify(value: value, root: root, path: path)
            } catch let error {
                throw CLIError.snapshot(error)
            }
        } else if action == "record" {
            let capability: WriteCapability
            do {
                capability = try FileSystemAuthority.grant(root: root)
            } catch let error {
                throw CLIError.platform(error)
            }
            do {
                let digest = try SnapshotEngine.record(value: value, path: path, capability: capability)
                print("snapshot=record digest=" + digest.rawValue)
            } catch let error {
                throw CLIError.snapshot(error)
            }
            return
        } else {
            throw CLIError.usage(action)
        }
        print("snapshot=" + action)
    }

    static func migrate(_ arguments: [String]) throws {
        guard arguments.count == 1 else {
            throw CLIError.usage("migrate")
        }
        let data: Data
        do {
            data = try FileSystemBoundary.read(path: arguments[0])
        } catch let error {
            throw CLIError.platform(error)
        }
        let value: JSONValue
        do {
            value = try StrictJSON.decode(data)
        } catch let error {
            throw CLIError.codec(error)
        }
        guard let text = String(data: StrictJSON.encode(value), encoding: .utf8) else {
            throw CLIError.usage("migrate-encoding")
        }
        print(text)
    }

    static func fix(_ arguments: [String]) throws {
        let report = try LawScanner.scan(root: root(from: arguments))
        for violation in report.violations {
            print(
                violation.location.file
                    + ":" + String(violation.location.line)
                    + ":" + String(violation.location.column)
                    + ":" + violation.law.rawValue
            )
        }
        if !report.passed {
            throw CLIError.laws(report.violations.count)
        }
    }

    static func makeReport(
        _ laws: LawReport,
        tests: TargetTestObservation,
        sourceDigest: Digest?
    ) throws -> AssuredReport {
        let encodedViolations = laws.violations.map {
            $0.law.rawValue + ":" + $0.location.file
        }.joined(separator: "\n")
        let testIdentity: String
        if let digest = tests.resultDigest {
            testIdentity = digest.rawValue
        } else {
            testIdentity = "no-test-result"
        }
        let sourceIdentity: String
        if let sourceDigest {
            sourceIdentity = sourceDigest.rawValue
        } else {
            sourceIdentity = "source-unverified"
        }
        let runDigest: Digest
        do {
            runDigest = try Digest.sha256(Data((sourceIdentity + "\n" + encodedViolations + "\n" + testIdentity).utf8))
        } catch let error {
            throw CLIError.digest(error)
        }
        let observations = LawCode.allCases.map { law in
            let failed = laws.violations.contains(where: { $0.law == law })
            return LawObservation(code: law.rawValue, status: failed ? .failed : .passed)
        }
        let run: RunID
        do {
            run = try .parse("run-" + runDigest.rawValue)
        } catch let error {
            throw CLIError.identifier(error)
        }
        let hostWorld: WorldID
        let packageSuite: TestID
        do {
            hostWorld = try .parse("world-host")
            packageSuite = try .parse("swift-package-suite")
        } catch let error {
            throw CLIError.identifier(error)
        }
        let worlds: [WorldID]
        let failures: [ExecutionFailure]
        switch tests {
        case .notConfigured:
            worlds = []
            failures = []
        case .passed(let count, _):
            worlds = count.rawValue == 0 ? [] : [hostWorld]
            failures = []
        case .failed:
            worlds = [hostWorld]
            failures = [.clean(.baselineTestFailed(packageSuite, hostWorld))]
        case .apparatus(let diagnostic):
            worlds = []
            failures = [.apparatus(.process(diagnostic))]
        }
        let catalog = EvidenceCatalog(
            run: run,
            scope: .complete,
            preservationClaims: [],
            detectionClaims: [],
            worlds: worlds,
            mutants: [],
            claimObservations: [],
            mutationObservations: [],
            lawObservations: observations,
            schemaObservations: [SchemaObservation(version: .v2, status: .passed)],
            failures: failures,
            review: IndependentReview(status: .pending, evidence: nil),
            executionCount: tests.executionCount
        )
        let closed: AuditedCatalog<Closed>
        do {
            closed = try AuditKernel.close(catalog)
        } catch let error {
            throw CLIError.audit(error)
        }
        do {
            return try AssuredReport(catalog: closed, faultEvidence: .unverified)
        } catch let error {
            throw CLIError.report(error)
        }
    }

    static func emitViolations(_ report: LawReport) throws {
        for violation in report.violations {
            print(
                violation.location.file
                    + ":" + String(violation.location.line)
                    + ":" + String(violation.location.column)
                    + ": " + violation.law.rawValue
                    + ": " + violation.subject
            )
        }
        if !report.passed {
            throw CLIError.laws(report.violations.count)
        }
    }

    static func readEnvelope(_ path: String) throws -> ReportEnvelope {
        let data: Data
        do {
            data = try FileSystemBoundary.read(path: path)
        } catch let error {
            throw CLIError.platform(error)
        }
        do {
            return try ReportCodec.decodeEnvelope(data)
        } catch let error {
            throw CLIError.report(error)
        }
    }

    static func validateReportOutput(_ output: String, repository: String) throws -> ExclusiveOutputOwner {
        let repositoryPath: String
        do {
            repositoryPath = try CanonicalPathBoundary.directory(repository)
        } catch let error {
            throw CLIError.platform(error)
        }
        let outputPath = output.hasPrefix("/")
            ? output : WorkingDirectoryBoundary.current() + "/" + output
        let prefix = repositoryPath.hasSuffix("/")
            ? repositoryPath : repositoryPath + "/"
        if outputPath == repositoryPath || outputPath.hasPrefix(prefix) {
            throw CLIError.outputInsideRepository(outputPath)
        }
        do {
            return try ExclusiveOutputOwner(absolutePath: outputPath)
        } catch let error {
            throw outputError(error)
        }
    }

    static func outputError(_ error: PlatformError) -> CLIError {
        if case .outputExists(let path) = error {
            return .outputExists(path)
        }
        return .platform(error)
    }

}
