import Foundation
import SwiftestLaws
import SwiftestModel
import SwiftestPlatform

enum LawToolFailure: Error {
    case usage
    case violations(Int)
    case path
    case platform(PlatformError)
}

@main
struct SwiftestLawTool {
    static func main() {
        do {
            try run()
        } catch {
            ProcessExitBoundary.fail(String(describing: error))
        }
    }

    static func run() throws {
        let arguments = CommandLine.arguments
        if arguments.count < 3 {
            throw LawToolFailure.usage
        }
        let root = arguments[1]
        let stamp = arguments[2]
        let report = try LawScanner.scan(
            root: root,
            declaredInputs: Array(arguments.dropFirst(3))
        )
        if !report.violations.isEmpty {
            for violation in report.violations {
                print(
                    violation.location.file
                        + ":" + String(violation.location.line)
                        + ":" + String(violation.location.column)
                        + ": " + violation.law.rawValue
                        + ": " + violation.subject
                )
            }
            throw LawToolFailure.violations(report.violations.count)
        }
        let url = URL(fileURLWithPath: stamp)
        let parent = url.deletingLastPathComponent().path
        let name: ArtifactPath
        do {
            name = try .parse(url.lastPathComponent)
        } catch {
            throw LawToolFailure.path
        }
        let capability: WriteCapability
        do {
            capability = try FileSystemAuthority.grant(root: parent)
        } catch let error {
            throw LawToolFailure.platform(error)
        }
        do {
            try FileSystemBoundary.write(
                Data("passed\n".utf8),
                relativePath: name,
                capability: capability
            )
        } catch let error {
            throw LawToolFailure.platform(error)
        }
    }
}
