import Foundation
import Swiftest
import SwiftestCodec
import SwiftestPlatform

enum SwiftPackageTestError: Error {
    case notPackage(String)
    case platform(PlatformError)
    case boundaryCampaign(SwiftPackageBoundaryCampaignError)
    case missingResult(Int32)
    case invalidInventory(XUnitCodecError)
}

struct SwiftPackageTestExecution {
    let observation: TargetTestObservation
    let boundaryRun: SwiftPackageBoundaryCampaignRun
}

struct SwiftPackageVerifyObservation {
    let tests: TargetTestObservation
    let boundaryFault: AuditedFaultCampaign?
}

enum SwiftPackageTestDriver {
    static func observeWithFaults(root: String) -> SwiftPackageVerifyObservation {
        let execution: SwiftPackageTestExecution
        do {
            execution = try execute(root: root)
        } catch let error {
            switch error {
            case .notPackage:
                return SwiftPackageVerifyObservation(tests: .notConfigured, boundaryFault: nil)
            case .platform, .boundaryCampaign, .missingResult:
                return SwiftPackageVerifyObservation(tests: .apparatus(Diagnostic(
                    code: .apparatusFailed,
                    subject: "swift-package",
                    detail: "test runner did not yield complete evidence"
                )), boundaryFault: nil)
            case .invalidInventory:
                return SwiftPackageVerifyObservation(tests: .apparatus(Diagnostic(
                    code: .invalidWire,
                    subject: "swift-package-inventory",
                    detail: "malformed discovered test inventory"
                )), boundaryFault: nil)
            }
        }
        let tests = execution.observation
        guard case .passed = tests else {
            return SwiftPackageVerifyObservation(tests: tests, boundaryFault: nil)
        }
        do {
            let fault = try execution.boundaryRun.audit()
            return SwiftPackageVerifyObservation(tests: tests, boundaryFault: fault)
        } catch {
            return SwiftPackageVerifyObservation(tests: .apparatus(Diagnostic(
                code: .apparatusFailed,
                subject: "swift-package-process-fault",
                detail: "process-launch injection did not fail closed"
            )), boundaryFault: nil)
        }
    }

    static func execute(root: String) throws(SwiftPackageTestError) -> SwiftPackageTestExecution {
        let manifest = root + "/Package.swift"
        let kind: FileEntryKind
        do {
            kind = try FileSystemBoundary.entryKind(path: manifest)
        } catch {
            throw .notPackage(root)
        }
        if kind != .file {
            throw .notPackage(root)
        }
        let scratch: ScratchDirectoryOwner
        do {
            scratch = try ScratchDirectoryOwner(
                parent: "/private/tmp",
                name: "swiftest-package-" + String(PlatformClock.monotonicNanoseconds().rawValue)
            )
        } catch let error {
            throw .platform(error)
        }
        let resultPath = scratch.path + "/tests.xml"
        let swiftTestingResultPath = scratch.path + "/tests-swift-testing.xml"
        let eventPath = scratch.path + "/swift-testing.jsonl"
        let sharedArguments = [
            "--package-path", root,
            "--scratch-path", scratch.path + "/build",
            "--cache-path", scratch.path + "/cache",
            "--config-path", scratch.path + "/config",
            "--security-path", scratch.path + "/security",
            "--disable-sandbox",
            "--disable-automatic-resolution",
            "--disable-index-store",
        ]
        let libraryArguments = ["--enable-xctest", "--enable-swift-testing"]
        let buildStatus: Int32
        do {
            buildStatus = try ProcessBoundary.runPinnedApple(
                executable: "/usr/bin/xcrun",
                arguments: ["swift", "build"] + sharedArguments + libraryArguments + ["--build-tests"],
                workingDirectory: root,
                scratch: scratch
            ).exitCode
        } catch let error {
            throw .platform(error)
        }
        if buildStatus != 0 {
            throw .missingResult(buildStatus)
        }
        let listing: ProcessOutput
        do {
            listing = try ProcessBoundary.runPinnedApple(
                executable: "/usr/bin/xcrun",
                arguments: ["swift", "test", "list"] + sharedArguments + libraryArguments + ["--skip-build"],
                workingDirectory: root,
                scratch: scratch
            )
        } catch let error {
            throw .platform(error)
        }
        let inventory: XUnitTestInventory
        do {
            inventory = try XUnitTestInventory.decode(listing.standardOutput)
        } catch let error {
            throw .invalidInventory(error)
        }
        let arguments = ["swift", "test"] + sharedArguments + libraryArguments + [
            "--skip-build",
            "--xunit-output=" + resultPath,
            "--event-stream-version", "6.4",
            "--event-stream-output-path=" + eventPath,
            "--parallel",
            "--num-workers", "1",
        ]
        let boundaryRun: SwiftPackageBoundaryCampaignRun
        do {
            boundaryRun = try SwiftPackageBoundaryFaultCampaign.run(
                executable: "/usr/bin/xcrun",
                arguments: arguments,
                workingDirectory: root,
                scratch: scratch,
                evidencePaths: SwiftPackageEvidencePaths(
                    xctest: resultPath,
                    swiftTesting: swiftTestingResultPath,
                    eventStream: eventPath
                ),
                discoveredTests: inventory
            )
        } catch let error {
            throw .boundaryCampaign(error)
        }
        return SwiftPackageTestExecution(
            observation: boundaryRun.observation,
            boundaryRun: boundaryRun
        )
    }
}
