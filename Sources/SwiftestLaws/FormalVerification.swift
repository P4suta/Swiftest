import Foundation
import SwiftestPlatform

public enum FormalVerificationError: Error, Equatable, Sendable {
    case platform(PlatformError)
    case untrustedProof(LeanTrustError)
    case snapshot(LeanProofSnapshotError)
    case oracleMismatch
}

public enum FormalVerification {
    private static let axiomAuditSource = """
        import Lean
        open Lean

        def trustedAxiom (name : Name) : Bool :=
          name == ``propext || name == ``Quot.sound || name == ``Classical.choice

        def main (args : List String) : IO Unit := do
          let modules := args.toArray.map String.toName
          unless modules.contains `SwiftestProofs && modules.contains `SwiftestProofs.Oracle do
            throw <| IO.userError "missing proof root or oracle module"
          let imports : Array Import := modules.map fun module => { module := module }
          let env ← importModules (loadExts := false) imports {}
          for module in modules do
            unless env.header.moduleNames.contains module do
              throw <| IO.userError s!"missing imported module {module}"
          let (audited, rejected) ← Lean.Core.CoreM.toIO'
              (ctx := {fileName := "", fileMap := default}) (s := {env}) do
            let mut audited := 0
            let mut rejected : Array String := #[]
            let env ← getEnv
            for (name, info) in env.constants.map₁ do
              if info.isTheorem || info.isAxiom then
                match env.getModuleIdxFor? name with
                | none => rejected := rejected.push s!"{name}: missing module origin"
                | some idx =>
                  match env.header.moduleNames[idx.toNat]? with
                  | none => rejected := rejected.push s!"{name}: invalid module origin"
                  | some module =>
                    if modules.contains module then
                      if info.isAxiom then
                        rejected := rejected.push s!"{name}: local axiom declaration"
                      else
                        audited := audited + 1
                        for ax in (← collectAxioms name) do
                          unless trustedAxiom ax do
                            rejected := rejected.push s!"{name}: {ax}"
            return (audited, rejected)
          if audited == 0 then
            throw <| IO.userError "empty theorem population"
          unless rejected.isEmpty do
            throw <| IO.userError (String.intercalate "; " rejected.toList)
          IO.println s!"axiom-audit=passed theorems={audited}"
        """

    public static func leanOracle(root: String) throws(FormalVerificationError) -> String {
        let snapshot = try makeSnapshot(root: root)
        let toolchain: PinnedLeanToolchain
        do {
            toolchain = try PinnedLeanToolchain.resolve()
        } catch let error {
            throw .platform(error)
        }
        try requireLake(["--rehash", "--wfail", "build"], toolchain: toolchain, snapshot: snapshot)
        do {
            try LeanTrust.auditManifest(root: snapshot.root)
        } catch let error {
            throw .untrustedProof(error)
        }
        try verify(snapshot)
        let artifacts = try makeBuildArtifacts(root: snapshot.root)
        for module in snapshot.proofModules {
            try requireSealedLake(
                ["env", toolchain.checker, "--fresh", module],
                toolchain: toolchain,
                snapshot: snapshot,
                artifacts: artifacts
            )
        }
        try requireSealedLake(
            ["env", toolchain.lean, "--run", "/dev/stdin"] + snapshot.proofModules,
            toolchain: toolchain,
            snapshot: snapshot,
            artifacts: artifacts,
            standardInput: Data(axiomAuditSource.utf8)
        )
        let oracle = try sealedLake(
            ["env", toolchain.lean, "--run", "SwiftestProofs/Oracle.lean"],
            toolchain: toolchain,
            snapshot: snapshot,
            artifacts: artifacts
        )
        return oracle.standardOutput
    }

    private static func makeSnapshot(root: String) throws(FormalVerificationError) -> LeanProofSnapshot {
        do {
            return try LeanProofSnapshot(sourceRoot: root)
        } catch let error {
            switch error {
            case .trust(let trust):
                throw .untrustedProof(trust)
            case .platform, .attributeAmbiguity, .path, .digest, .changed:
                throw .snapshot(error)
            }
        }
    }

    private static func makeBuildArtifacts(root: String) throws(FormalVerificationError) -> LeanBuildArtifactSeal {
        do {
            return try LeanBuildArtifactSeal(root: root)
        } catch let error {
            throw .snapshot(error)
        }
    }

    public static func verifyOracle(
        root: String,
        swiftOracle: String
    ) throws(FormalVerificationError) {
        let lean = try leanOracle(root: root)
        if lean != swiftOracle {
            throw .oracleMismatch
        }
    }

    private static func requireLake(
        _ arguments: [String],
        toolchain: PinnedLeanToolchain,
        snapshot: borrowing LeanProofSnapshot
    ) throws(FormalVerificationError) {
        let output = try lake(arguments, toolchain: toolchain, snapshot: snapshot)
        if output.exitCode != 0 {
            throw .platform(.processExit("lake", output.exitCode, output.failureDetail))
        }
    }

    private static func lake(
        _ arguments: [String],
        toolchain: PinnedLeanToolchain,
        snapshot: borrowing LeanProofSnapshot,
        standardInput: Data? = nil
    ) throws(FormalVerificationError) -> ProcessOutput {
        try verify(snapshot)
        let output: ProcessOutput
        do {
            output = try snapshot.runPinnedLean(
                toolchain: toolchain,
                arguments: arguments,
                standardInput: standardInput
            )
        } catch let error {
            try verify(snapshot)
            throw .platform(error)
        }
        try verify(snapshot)
        return output
    }

    private static func requireSealedLake(
        _ arguments: [String],
        toolchain: PinnedLeanToolchain,
        snapshot: borrowing LeanProofSnapshot,
        artifacts: borrowing LeanBuildArtifactSeal,
        standardInput: Data? = nil
    ) throws(FormalVerificationError) {
        let output = try sealedLake(
            arguments,
            toolchain: toolchain,
            snapshot: snapshot,
            artifacts: artifacts,
            standardInput: standardInput
        )
        if output.exitCode != 0 {
            throw .platform(.processExit("lake", output.exitCode, output.failureDetail))
        }
    }

    private static func sealedLake(
        _ arguments: [String],
        toolchain: PinnedLeanToolchain,
        snapshot: borrowing LeanProofSnapshot,
        artifacts: borrowing LeanBuildArtifactSeal,
        standardInput: Data? = nil
    ) throws(FormalVerificationError) -> ProcessOutput {
        try verify(artifacts)
        let output: ProcessOutput
        do {
            output = try lake(
                arguments,
                toolchain: toolchain,
                snapshot: snapshot,
                standardInput: standardInput
            )
        } catch let error {
            try verify(artifacts)
            throw error
        }
        try verify(artifacts)
        return output
    }

    private static func verify(_ snapshot: borrowing LeanProofSnapshot) throws(FormalVerificationError) {
        do {
            try snapshot.verifyUnchanged()
        } catch let error {
            throw .snapshot(error)
        }
    }

    private static func verify(_ artifacts: borrowing LeanBuildArtifactSeal) throws(FormalVerificationError) {
        do {
            try artifacts.verifyUnchanged()
        } catch let error {
            throw .snapshot(error)
        }
    }
}
