import SwiftestPlatform

public enum FormalVerificationError: Error, Equatable, Sendable {
    case platform(PlatformError)
    case untrustedProof(LeanTrustError)
    case oracleMismatch
}

public enum FormalVerification {
    public static func leanOracle(root: String) throws(FormalVerificationError) -> String {
        do {
            try LeanTrust.audit(root: root)
        } catch let error {
            throw .untrustedProof(error)
        }
        let build: ProcessOutput
        do {
            build = try ProcessBoundary.run(
                executable: "/usr/bin/env",
                arguments: ["lake", "--wfail", "build"],
                workingDirectory: root
            )
        } catch let error {
            throw .platform(error)
        }
        if build.exitCode != 0 {
            throw .platform(.processExit("lake", build.exitCode, build.standardOutput))
        }
        do {
            try LeanTrust.auditManifest(root: root)
        } catch let error {
            throw .untrustedProof(error)
        }
        do {
            return try ProcessBoundary.run(
                executable: "/usr/bin/env",
                arguments: ["lake", "env", "lean", "--run", "SwiftestProofs/Oracle.lean"],
                workingDirectory: root
            ).standardOutput
        } catch let error {
            throw .platform(error)
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
}
