import SwiftestModel

public enum SATError: Error, Equatable, Sendable {
    case invalidVariable(Int)
    case emptyClause
    case variableLimit(Int)
    case incompleteCertificate(SATVariable)
    case invalidCertificate
}

public struct SATVariable: Hashable, Sendable, Comparable {
    public let rawValue: Int

    private init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func make(_ value: Int) throws(SATError) -> SATVariable {
        if value <= 0 {
            throw .invalidVariable(value)
        }
        return SATVariable(rawValue: value)
    }

    public static func < (lhs: SATVariable, rhs: SATVariable) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum SATLiteral: Hashable, Sendable {
    case positive(SATVariable)
    case negative(SATVariable)

    public var variable: SATVariable {
        switch self {
        case .positive(let variable), .negative(let variable):
            variable
        }
    }
}

public struct SATClause: Hashable, Sendable {
    public let literals: [SATLiteral]

    private init(literals: [SATLiteral]) {
        self.literals = literals
    }

    public static func make(_ literals: [SATLiteral]) throws(SATError) -> SATClause {
        if literals.isEmpty {
            throw .emptyClause
        }
        return SATClause(literals: literals)
    }
}

public struct SATFormula: Hashable, Sendable {
    public let clauses: [SATClause]

    public init(clauses: [SATClause]) {
        self.clauses = clauses
    }

    public var variables: [SATVariable] {
        Array(Set(clauses.flatMap(\.literals).map(\.variable))).sorted()
    }
}

public enum SATTruth: String, CaseIterable, Hashable, Sendable {
    case falseValue = "false"
    case trueValue = "true"
}

public struct SATCertificate: Equatable, Sendable {
    public let assignments: [SATVariable: SATTruth]

    public init(assignments: [SATVariable: SATTruth]) {
        self.assignments = assignments
    }
}

public struct UnsatisfiableCertificate: Equatable, Sendable {
    public let checkedAssignments: EvidenceCount

    public init(checkedAssignments: EvidenceCount) {
        self.checkedAssignments = checkedAssignments
    }
}

public enum SATResult: Equatable, Sendable {
    case satisfiable(SATCertificate)
    case unsatisfiable(UnsatisfiableCertificate)
}

private enum PartialTruth {
    case falseValue
    case trueValue
    case unknown
}

public enum SATSolver {
    public static func solve(_ formula: SATFormula) throws(SATError) -> SATResult {
        let variables = formula.variables
        if variables.count > 24 {
            throw .variableLimit(variables.count)
        }
        var checked = 0
        if let assignments = search(
            formula: formula,
            variables: variables,
            index: 0,
            assignments: [:],
            checked: &checked
        ) {
            return .satisfiable(SATCertificate(assignments: assignments))
        }
        let count: EvidenceCount
        do {
            count = try EvidenceCount.nonnegative(checked)
        } catch {
            throw .variableLimit(variables.count)
        }
        return .unsatisfiable(UnsatisfiableCertificate(checkedAssignments: count))
    }

    private static func search(
        formula: SATFormula,
        variables: [SATVariable],
        index: Int,
        assignments: [SATVariable: SATTruth],
        checked: inout Int
    ) -> [SATVariable: SATTruth]? {
        if formula.clauses.contains(where: { clauseValue($0, assignments: assignments) == .falseValue }) {
            checked += 1
            return nil
        }
        if formula.clauses.allSatisfy({ clauseValue($0, assignments: assignments) == .trueValue }) {
            checked += 1
            return assignments
        }
        if index >= variables.count {
            checked += 1
            return nil
        }
        let variable = variables[index]
        if assignments[variable] != nil {
            return search(
                formula: formula,
                variables: variables,
                index: index + 1,
                assignments: assignments,
                checked: &checked
            )
        }
        var falseAssignments = assignments
        falseAssignments[variable] = .falseValue
        if let result = search(
            formula: formula,
            variables: variables,
            index: index + 1,
            assignments: falseAssignments,
            checked: &checked
        ) {
            return result
        }
        var trueAssignments = assignments
        trueAssignments[variable] = .trueValue
        return search(
            formula: formula,
            variables: variables,
            index: index + 1,
            assignments: trueAssignments,
            checked: &checked
        )
    }

    private static func clauseValue(
        _ clause: SATClause,
        assignments: [SATVariable: SATTruth]
    ) -> PartialTruth {
        var hasUnknown = false
        for literal in clause.literals {
            guard let assignment = assignments[literal.variable] else {
                hasUnknown = true
                continue
            }
            switch (literal, assignment) {
            case (.positive, .trueValue), (.negative, .falseValue):
                return .trueValue
            case (.positive, .falseValue), (.negative, .trueValue):
                continue
            }
        }
        return hasUnknown ? .unknown : .falseValue
    }
}

public enum SATProofKernel {
    public static func verify(
        formula: SATFormula,
        certificate: SATCertificate
    ) throws(SATError) {
        for variable in formula.variables {
            if certificate.assignments[variable] == nil {
                throw .incompleteCertificate(variable)
            }
        }
        for clause in formula.clauses {
            let satisfied = clause.literals.contains { literal in
                guard let value = certificate.assignments[literal.variable] else {
                    return false
                }
                switch (literal, value) {
                case (.positive, .trueValue), (.negative, .falseValue):
                    return true
                case (.positive, .falseValue), (.negative, .trueValue):
                    return false
                }
            }
            if !satisfied {
                throw .invalidCertificate
            }
        }
    }
}
