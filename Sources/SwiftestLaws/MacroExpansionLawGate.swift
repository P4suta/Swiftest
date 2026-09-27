public enum MacroExpansionInspection: Equatable, Sendable {
    case accepted
    case rejected([LawViolation])
}

public enum MacroExpansionRole: String, Sendable {
    case member
    case body
    case expression
}

public enum MacroExpansionLawGate {
    public static func inspect(_ source: String, role: MacroExpansionRole) -> MacroExpansionInspection {
        let contextualSource: String
        switch role {
        case .member:
            contextualSource = "enum __SwiftestMacroScope {\n" + source + "\n}\n"
        case .body:
            contextualSource = "func __swiftestMacroScope() {\n" + source + "\n}\n"
        case .expression:
            contextualSource = "func __swiftestMacroScope() {\nlet __swiftestExpression = (\n" + source + "\n)\n}\n"
        }
        let violations = LawScanner.scanSwiftSource(
            contextualSource,
            path: "Sources/SwiftestMacros/Expanded.swift"
        )
        if violations.isEmpty {
            return .accepted
        }
        return .rejected(violations)
    }
}
