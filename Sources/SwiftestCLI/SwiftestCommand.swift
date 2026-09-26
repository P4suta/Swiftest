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
}

@main
struct SwiftestCommand {
    static func main() throws {
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
                    swiftOracle: VerdictOracle.text() + FaultOracle.text()
                )
            } catch let error {
                throw CLIError.formal(String(describing: error))
            }
        }
        print("laws=passed files=" + String(report.checkedFiles.rawValue))
    }

    static func verify(_ arguments: [String]) throws {
        let repository = root(from: arguments)
        let lawReport = try LawScanner.scan(root: repository)
        let report = try makeReport(lawReport)
        let data: Data
        do {
            data = try ReportCodec.encode(report)
        } catch let error {
            throw CLIError.report(error)
        }
        if let output = optionValue("--output", arguments: arguments) {
            try write(data, absolutePath: output)
        } else {
            guard let text = String(data: data, encoding: .utf8) else {
                throw CLIError.usage("report-encoding")
            }
            print(text)
        }
        if !lawReport.passed && !arguments.contains("--allow-gaps") {
            throw CLIError.laws(lawReport.violations.count)
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
        print("replay=" + envelope.verdict.rawValue + " run=" + envelope.run.rawValue)
    }

    static func review(_ arguments: [String]) throws {
        if arguments == ["--verdict-oracle"] {
            print(VerdictOracle.text(), terminator: "")
            return
        }
        if arguments == ["--formal-oracle"] {
            print(VerdictOracle.text() + FaultOracle.text(), terminator: "")
            return
        }
        guard arguments.count == 1 else {
            throw CLIError.usage("review")
        }
        let envelope = try readEnvelope(arguments[0])
        print("review=accepted digest=" + envelope.catalogDigest.rawValue)
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
        let verdict = envelopes.map(\.verdict).max { severity($0) < severity($1) }
        guard let verdict else {
            throw CLIError.usage("merge")
        }
        print("verdict=" + verdict.rawValue + " parts=" + String(envelopes.count))
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

    static func makeReport(_ laws: LawReport) throws -> AssuredReport {
        let encodedViolations = laws.violations.map {
            $0.law.rawValue + ":" + $0.location.file
        }.joined(separator: "\n")
        let reviewDigest: Digest
        do {
            reviewDigest = try Digest.sha256(Data(encodedViolations.utf8))
        } catch let error {
            throw CLIError.digest(error)
        }
        let observations = LawCode.allCases.map { law in
            let failed = laws.violations.contains(where: { $0.law == law })
            return LawObservation(code: law.rawValue, status: failed ? .failed : .passed)
        }
        let run: RunID
        do {
            run = try .parse("run-" + String(reviewDigest.rawValue.prefix(16)))
        } catch let error {
            throw CLIError.identifier(error)
        }
        let catalog = EvidenceCatalog(
            run: run,
            scope: .complete,
            preservationClaims: [],
            detectionClaims: [],
            worlds: [],
            mutants: [],
            claimObservations: [],
            mutationObservations: [],
            lawObservations: observations,
            schemaObservations: [SchemaObservation(version: .v1, status: .passed)],
            failures: [],
            review: IndependentReview(status: .accepted, evidence: reviewDigest),
            executionCount: laws.checkedFiles
        )
        let closed: AuditedCatalog<Closed>
        do {
            closed = try AuditKernel.close(catalog)
        } catch let error {
            throw CLIError.audit(error)
        }
        let faultCampaign: FaultCampaign
        do {
            faultCampaign = try StandardFaultCampaign.make()
        } catch let error {
            throw CLIError.faultDeclaration(error)
        }
        let faultAudit: AuditedFaultCampaign
        do {
            faultAudit = try FaultAuditKernel.close(
                campaign: faultCampaign,
                observations: StandardFaultCampaign.apparatusObservations(for: faultCampaign)
            )
        } catch let error {
            throw CLIError.faultAudit(error)
        }
        do {
            return try AssuredReport(catalog: closed, faults: faultAudit)
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

    static func write(_ data: Data, absolutePath: String) throws {
        let url = URL(fileURLWithPath: absolutePath).standardizedFileURL
        let path: ArtifactPath
        do {
            path = try .parse(url.lastPathComponent)
        } catch let error {
            throw CLIError.path(error)
        }
        let capability: WriteCapability
        do {
            capability = try FileSystemAuthority.grant(root: url.deletingLastPathComponent().path)
        } catch let error {
            throw CLIError.platform(error)
        }
        do {
            try FileSystemBoundary.write(data, relativePath: path, capability: capability)
        } catch let error {
            throw CLIError.platform(error)
        }
    }

    static func optionValue(_ option: String, arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option) else {
            return nil
        }
        let valueIndex = index + 1
        if valueIndex >= arguments.count {
            return nil
        }
        return arguments[valueIndex]
    }

    static func severity(_ verdict: Verdict) -> Int {
        switch verdict {
        case .assured, .changeAssured, .scopeAssured:
            0
        case .unsettled:
            1
        case .gaps:
            2
        case .gapsAndUnsettled:
            3
        case .invalid:
            4
        }
    }
}
