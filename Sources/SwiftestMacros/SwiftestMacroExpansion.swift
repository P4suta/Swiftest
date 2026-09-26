import SwiftParser
import SwiftSyntax
import SwiftestCodec

enum SwiftestMacroExpansionError: Error, Equatable {
    case expectedEnum
    case emptyDomain
    case genericDomain
    case associatedValue(String)
    case conditionalCase
    case attributedCase
    case reservedMember(String)
    case invalidInvocation
    case invalidTemporalArguments
    case expectedGlobalFunction
    case invalidWorldFunction
    case invalidPropertyFunction
    case invalidStateMachineFunction
    case unavailablePerformanceClaim
    case unavailableTestDouble
    case invalidAttributeArguments
    case unknownMacro(String)

    var message: String {
        switch self {
        case .expectedEnum: "@ClosedDomain requires an enum"
        case .emptyDomain: "@ClosedDomain requires at least one case"
        case .genericDomain: "@ClosedDomain does not support generic enums"
        case .associatedValue(let name): "@ClosedDomain case \(name) has associated values"
        case .conditionalCase: "@ClosedDomain does not support conditional cases"
        case .attributedCase: "@ClosedDomain does not support attributed cases"
        case .reservedMember(let name): "@ClosedDomain owns member \(name)"
        case .invalidInvocation: "macro invocation is malformed"
        case .invalidTemporalArguments: "temporal macro requires a count and condition closure"
        case .expectedGlobalFunction: "macro requires a global function"
        case .invalidWorldFunction: "world test requires @Test on an async throwing function without parameters or body statements"
        case .invalidPropertyFunction: "property requires @Test on a synchronous throwing function without parameters or body statements"
        case .invalidStateMachineFunction: "state-machine test requires @Test on a synchronous throwing function without parameters or body statements"
        case .unavailablePerformanceClaim: "PerformanceClaim is not assured in this version"
        case .unavailableTestDouble: "TestDouble is not assured in this version"
        case .invalidAttributeArguments: "macro attribute arguments are malformed"
        case .unknownMacro(let name): "unknown Swiftest macro \(name)"
        }
    }
}

enum SwiftestMacroExpansion {
    static func expand(
        typeName: String,
        role: String,
        source: String,
        attributeSource: String,
        parentSource: String?
    ) throws(SwiftestMacroExpansionError) -> String {
        switch typeName {
        case "ClosedDomainMacro":
            guard role == "member" else {
                throw .invalidInvocation
            }
            return try closedDomain(source)
        case "EventuallyMacro":
            return try temporal(source, role: role, method: "eventually", countLabel: "attempts")
        case "InvariantMacro":
            return try temporal(source, role: role, method: "invariant", countLabel: "observations")
        case "NeverMacro":
            return try temporal(source, role: role, method: "never", countLabel: "observations")
        case "WorldTestMacro":
            return try SwiftestBodyMacroExpansion.world(
                source: source,
                attributeSource: attributeSource,
                parentSource: parentSource,
                role: role,
                kind: .model
            )
        case "WorldUITestMacro":
            return try SwiftestBodyMacroExpansion.world(
                source: source,
                attributeSource: attributeSource,
                parentSource: parentSource,
                role: role,
                kind: .ui
            )
        case "PropertyMacro":
            return try SwiftestBodyMacroExpansion.property(
                source: source,
                attributeSource: attributeSource,
                parentSource: parentSource,
                role: role
            )
        case "StateMachineTestMacro":
            return try SwiftestBodyMacroExpansion.stateMachine(
                source: source,
                attributeSource: attributeSource,
                parentSource: parentSource,
                role: role
            )
        case "PerformanceClaimMacro":
            throw .unavailablePerformanceClaim
        case "TestDoubleMacro":
            throw .unavailableTestDouble
        default:
            throw .unknownMacro(typeName)
        }
    }

    private static func closedDomain(_ source: String) throws(SwiftestMacroExpansionError) -> String {
        let parsed = Parser.parse(source: source)
        guard let declaration = parsed.statements.first?.item.as(EnumDeclSyntax.self) else {
            throw .expectedEnum
        }
        guard declaration.genericParameterClause == nil else {
            throw .genericDomain
        }
        let reserved: Set<String> = ["cases", "code", "schema", "testSpecimens"]
        var caseTokens: [String] = []
        var codeNames: [String] = []
        for member in declaration.memberBlock.members {
            if let caseDeclaration = member.decl.as(EnumCaseDeclSyntax.self) {
                guard caseDeclaration.attributes.isEmpty else {
                    throw .attributedCase
                }
                for element in caseDeclaration.elements {
                    let token = element.name.text
                    guard element.parameterClause == nil else {
                        throw .associatedValue(token)
                    }
                    caseTokens.append(token)
                    codeNames.append(identifierCode(token))
                }
            } else if member.decl.is(IfConfigDeclSyntax.self) {
                throw .conditionalCase
            } else if let variable = member.decl.as(VariableDeclSyntax.self) {
                for binding in variable.bindings {
                    if let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                        reserved.contains(identifier.identifier.text) {
                        throw .reservedMember(identifier.identifier.text)
                    }
                }
            } else if let function = member.decl.as(FunctionDeclSyntax.self),
                reserved.contains(function.name.text) {
                throw .reservedMember(function.name.text)
            }
        }
        guard !caseTokens.isEmpty else {
            throw .emptyDomain
        }
        let access = declaration.modifiers.map(\.name.text).first {
            ["public", "package", "fileprivate", "private"].contains($0)
        }
        let prefix: String
        if let access {
            prefix = access + " "
        } else {
            prefix = ""
        }
        let caseReferences = caseTokens.map { "." + $0 }.joined(separator: ", ")
        let switchArms = zip(caseTokens, codeNames).map { token, code in
            "case .\(token): return \(swiftString(code))"
        }.joined(separator: "\n")
        let schema = StrictJSON.render(.object([
            "additionalProperties": .boolean(false),
            "enum": .array(codeNames.map(JSONValue.string)),
            "title": .string(identifierCode(declaration.name.text)),
            "type": .string("string"),
        ]))
        return """
        \(prefix)static let cases: [Self] = [\(caseReferences)]
        \(prefix)var code: String {
            switch self {
            \(switchArms)
            }
        }
        \(prefix)static let schema: String = \(swiftString(schema))
        \(prefix)static let testSpecimens: [Self] = cases
        """
    }

    private static func temporal(
        _ source: String,
        role: String,
        method: String,
        countLabel: String
    ) throws(SwiftestMacroExpansionError) -> String {
        guard role == "expression" else {
            throw .invalidInvocation
        }
        let parsed = Parser.parse(source: source)
        guard let invocation = parsed.statements.first?.item.as(MacroExpansionExprSyntax.self) else {
            throw .invalidInvocation
        }
        let arguments = Array(invocation.arguments)
        guard let count = arguments.first,
            count.label?.text == countLabel,
            invocation.additionalTrailingClosures.isEmpty else {
            throw .invalidTemporalArguments
        }
        let condition: String
        if arguments.count == 1, let trailing = invocation.trailingClosure {
            condition = trailing.description
        } else if arguments.count == 2,
            invocation.trailingClosure == nil,
            arguments[1].label == nil,
            let inline = arguments[1].expression.as(ClosureExprSyntax.self) {
            condition = inline.description
        } else {
            throw .invalidTemporalArguments
        }
        return "SwiftestTesting.TemporalAssertions.\(method)(\(countLabel): \(count.expression.description), condition: \(condition))"
    }

    private static func identifierCode(_ token: String) -> String {
        if token.hasPrefix("`"), token.hasSuffix("`"), token.count >= 2 {
            return String(token.dropFirst().dropLast())
        }
        return token
    }

    private static func swiftString(_ value: String) -> String {
        StrictJSON.render(.string(value))
    }
}
