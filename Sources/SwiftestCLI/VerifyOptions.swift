import Foundation
import SwiftestPlatform

enum GapPolicy {
    case requireAssurance
    case allowGaps
}

enum VerifyTarget {
    case automatic
    case xcode(scheme: String, destination: String, project: String?, workspace: String?)
}

enum VerifyLawDomain {
    case selfRepository
    case externalSwiftPackage
    case externalXcode
}

struct VerifyOptions {
    let root: String
    let output: String?
    let gapPolicy: GapPolicy
    let target: VerifyTarget
    let lawDomain: VerifyLawDomain

    static func parse(_ arguments: [String]) throws(CLIError) -> VerifyOptions {
        var root: String?
        var output: String?
        var scheme: String?
        var destination: String?
        var project: String?
        var workspace: String?
        var explicitLawDomain: VerifyLawDomain?
        var gapPolicy = GapPolicy.requireAssurance
        var sawGapOption = false
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--allow-gaps":
                if sawGapOption {
                    throw .usage(argument)
                }
                sawGapOption = true
                gapPolicy = .allowGaps
            case "--self-laws":
                if explicitLawDomain != nil {
                    throw .usage(argument)
                }
                explicitLawDomain = .selfRepository
            case "--output", "--scheme", "--destination", "--project", "--workspace":
                let valueIndex = index + 1
                if valueIndex >= arguments.count || arguments[valueIndex].hasPrefix("--") {
                    throw .usage(argument)
                }
                let value = arguments[valueIndex]
                if value.isEmpty {
                    throw .usage(argument)
                }
                switch argument {
                case "--output":
                    if output != nil { throw .usage(argument) }
                    output = value
                case "--scheme":
                    if scheme != nil { throw .usage(argument) }
                    scheme = value
                case "--destination":
                    if destination != nil { throw .usage(argument) }
                    destination = value
                case "--project":
                    if project != nil { throw .usage(argument) }
                    project = value
                case "--workspace":
                    if workspace != nil { throw .usage(argument) }
                    workspace = value
                default:
                    throw .usage(argument)
                }
                index = valueIndex
            default:
                if argument.hasPrefix("--") || root != nil {
                    throw .usage(argument)
                }
                root = argument
            }
            index += 1
        }
        if project != nil && workspace != nil {
            throw .usage("project-or-workspace")
        }
        let target: VerifyTarget
        let lawDomain: VerifyLawDomain
        if let scheme, let destination {
            if explicitLawDomain != nil {
                throw .usage("self-laws-with-xcode")
            }
            target = .xcode(scheme: scheme, destination: destination, project: project, workspace: workspace)
            lawDomain = .externalXcode
        } else if scheme != nil || destination != nil || project != nil || workspace != nil {
            throw .usage("xcode-scheme-and-destination")
        } else {
            target = .automatic
            if let explicitLawDomain {
                lawDomain = explicitLawDomain
            } else {
                lawDomain = .externalSwiftPackage
            }
        }
        let repository: String
        if let root {
            repository = root
        } else {
            repository = WorkingDirectoryBoundary.current()
        }
        return VerifyOptions(
            root: repository,
            output: output,
            gapPolicy: gapPolicy,
            target: target,
            lawDomain: lawDomain
        )
    }
}
