import SwiftParser
import SwiftSyntax

enum WorldTestKind {
    case model
    case ui
}

enum SwiftestBodyMacroExpansion {
    static func world(
        source: String,
        attributeSource: String,
        parentSource: String?,
        role: String,
        kind: WorldTestKind
    ) throws(SwiftestMacroExpansionError) -> String {
        guard role == "body" else {
            throw .invalidInvocation
        }
        let function = try globalFunction(source, parentSource: parentSource)
        guard function.genericParameterClause == nil,
            function.genericWhereClause == nil,
            function.signature.returnClause == nil,
            function.signature.effectSpecifiers?.asyncSpecifier != nil,
            function.signature.effectSpecifiers?.throwsClause != nil,
            function.signature.parameterClause.parameters.isEmpty,
            hasTestingAttribute(function),
            let body = function.body,
            body.statements.isEmpty else {
            throw .invalidWorldFunction
        }
        let arguments = try attributeArguments(attributeSource, expected: ["worlds", "body"])
        guard let worlds = arguments["worlds"],
            let worldBody = arguments["body"] else {
            throw .invalidAttributeArguments
        }
        return """
        let __swiftestWorlds = try (\(worlds)).allWorlds()
        for world in __swiftestWorlds {
            do {
                try await (\(worldBody))(world)
            } catch {
                Testing.Issue.record(error)
            }
        }
        """
    }

    static func property(
        source: String,
        attributeSource: String,
        parentSource: String?,
        role: String
    ) throws(SwiftestMacroExpansionError) -> String {
        guard role == "body" else {
            throw .invalidInvocation
        }
        let function = try globalFunction(source, parentSource: parentSource)
        guard function.genericParameterClause == nil,
            function.genericWhereClause == nil,
            function.signature.returnClause == nil,
            function.signature.effectSpecifiers?.asyncSpecifier == nil,
            function.signature.effectSpecifiers?.throwsClause != nil,
            function.signature.parameterClause.parameters.isEmpty,
            hasTestingAttribute(function),
            let body = function.body,
            body.statements.isEmpty else {
            throw .invalidPropertyFunction
        }
        let arguments = try attributeArguments(
            attributeSource,
            expected: ["iterations", "seed", "range", "predicate"]
        )
        guard let iterations = arguments["iterations"],
            let seed = arguments["seed"],
            let range = arguments["range"],
            let predicate = arguments["predicate"] else {
            throw .invalidAttributeArguments
        }
        let name = function.name.text
        return """
        let generator = try SwiftestEngine.PropertyGenerator<Int>.integers(in: \(range))
        let result = try SwiftestEngine.PropertyRunner.check(
            iterations: \(iterations),
            seed: \(seed),
            generator: generator,
            shrinker: SwiftestEngine.PropertyShrinker<Int>.towardZero,
            predicate: \(predicate)
        )
        switch result {
        case .passed:
            break
        case .failed(let value, let iteration):
            Testing.Issue.record("property \(name) failed at iteration \\(iteration.rawValue) with value \\(value)")
        }
        """
    }

    static func stateMachine(
        source: String,
        attributeSource: String,
        parentSource: String?,
        role: String
    ) throws(SwiftestMacroExpansionError) -> String {
        guard role == "body" else {
            throw .invalidInvocation
        }
        let function = try globalFunction(source, parentSource: parentSource)
        guard function.genericParameterClause == nil,
            function.genericWhereClause == nil,
            function.signature.returnClause == nil,
            function.signature.effectSpecifiers?.asyncSpecifier == nil,
            function.signature.effectSpecifiers?.throwsClause != nil,
            function.signature.parameterClause.parameters.isEmpty,
            hasTestingAttribute(function),
            let body = function.body,
            body.statements.isEmpty else {
            throw .invalidStateMachineFunction
        }
        let arguments = try attributeArguments(attributeSource, expected: ["model", "depth"])
        guard let model = arguments["model"],
            let depth = arguments["depth"] else {
            throw .invalidAttributeArguments
        }
        let name = function.name.text
        return """
        let result = try SwiftestTesting.StateMachineRunner.explore(model: \(model), depth: \(depth))
        switch result {
        case .passed:
            break
        case .failed(let trace):
            Testing.Issue.record("state machine \(name) failed after \\(trace.count) transitions")
        }
        """
    }

    private static func globalFunction(
        _ source: String,
        parentSource: String?
    ) throws(SwiftestMacroExpansionError) -> FunctionDeclSyntax {
        guard parentSource == nil else {
            throw .expectedGlobalFunction
        }
        let parsed = Parser.parse(source: source)
        guard let function = parsed.statements.first?.item.as(FunctionDeclSyntax.self),
            function.body != nil else {
            throw .expectedGlobalFunction
        }
        return function
    }

    private static func attributeArguments(
        _ source: String,
        expected: Set<String>
    ) throws(SwiftestMacroExpansionError) -> [String: String] {
        let parsed = Parser.parse(source: source + "\nfunc __swiftest_attribute_placeholder() {}")
        guard let function = parsed.statements.first?.item.as(FunctionDeclSyntax.self),
            let attribute = function.attributes.first?.as(AttributeSyntax.self),
            let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
            throw .invalidAttributeArguments
        }
        var fields: [String: String] = [:]
        for argument in arguments {
            guard let label = argument.label?.text,
                expected.contains(label),
                fields[label] == nil else {
                throw .invalidAttributeArguments
            }
            let value = argument.expression.trimmedDescription
            guard !value.isEmpty else {
                throw .invalidAttributeArguments
            }
            fields[label] = value
        }
        guard Set(fields.keys) == expected else {
            throw .invalidAttributeArguments
        }
        return fields
    }

    private static func hasTestingAttribute(_ function: FunctionDeclSyntax) -> Bool {
        function.attributes.contains { element in
            guard let attribute = element.as(AttributeSyntax.self) else {
                return false
            }
            return ["Test", "Testing.Test"].contains(attribute.attributeName.trimmedDescription)
        }
    }
}
