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
    public let verificationDomainSize: EvidenceCount

    init(verificationDomainSize: EvidenceCount) {
        self.verificationDomainSize = verificationDomainSize
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
        if let assignments = search(
            formula: formula,
            variables: variables,
            index: 0,
            assignments: [:]
        ) {
            return .satisfiable(SATCertificate(assignments: assignments))
        }
        let count: EvidenceCount
        do {
            count = try EvidenceCount.nonnegative(1 << variables.count)
        } catch {
            throw .variableLimit(variables.count)
        }
        return .unsatisfiable(UnsatisfiableCertificate(verificationDomainSize: count))
    }

    private static func search(
        formula: SATFormula,
        variables: [SATVariable],
        index: Int,
        assignments: [SATVariable: SATTruth]
    ) -> [SATVariable: SATTruth]? {
        if formula.clauses.contains(where: { clauseValue($0, assignments: assignments) == .falseValue }) {
            return nil
        }
        if formula.clauses.allSatisfy({ clauseValue($0, assignments: assignments) == .trueValue }) {
            var complete = assignments
            for variable in variables where complete[variable] == nil {
                complete[variable] = .falseValue
            }
            return complete
        }
        if index >= variables.count {
            return nil
        }
        let variable = variables[index]
        if assignments[variable] != nil {
            return search(
                formula: formula,
                variables: variables,
                index: index + 1,
                assignments: assignments
            )
        }
        var falseAssignments = assignments
        falseAssignments[variable] = .falseValue
        if let result = search(
            formula: formula,
            variables: variables,
            index: index + 1,
            assignments: falseAssignments
        ) {
            return result
        }
        var trueAssignments = assignments
        trueAssignments[variable] = .trueValue
        return search(
            formula: formula,
            variables: variables,
            index: index + 1,
            assignments: trueAssignments
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
        certificate: UnsatisfiableCertificate
    ) throws(SATError) {
        let variables = formula.variables
        if variables.count > 24 {
            throw .variableLimit(variables.count)
        }
        if certificate.verificationDomainSize.rawValue != 1 << variables.count {
            throw .invalidCertificate
        }
        var positions: [SATVariable: Int] = [:]
        for (index, variable) in variables.enumerated() {
            positions[variable] = index
        }
        for assignment in 0..<(1 << variables.count) {
            var formulaSatisfied = true
            for clause in formula.clauses {
                var clauseSatisfied = false
                for literal in clause.literals {
                    guard let position = positions[literal.variable] else {
                        throw .invalidCertificate
                    }
                    let value = (assignment & (1 << position)) != 0
                    switch literal {
                    case .positive:
                        clauseSatisfied = clauseSatisfied || value
                    case .negative:
                        clauseSatisfied = clauseSatisfied || !value
                    }
                }
                if !clauseSatisfied {
                    formulaSatisfied = false
                    break
                }
            }
            if formulaSatisfied {
                throw .invalidCertificate
            }
        }
    }

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

public enum SATOracle {
    public static func text() throws(SATError) -> String {
        let first = try SATVariable.make(1)
        let second = try SATVariable.make(2)
        let literals: [(name: String, literal: SATLiteral)] = [
            ("x", .positive(first)),
            ("not-x", .negative(first)),
            ("y", .positive(second)),
            ("not-y", .negative(second)),
        ]
        var lines: [String] = []
        for left in literals {
            for right in literals {
                let formula = SATFormula(clauses: [
                    try SATClause.make([left.literal]),
                    try SATClause.make([right.literal]),
                ])
                let outcome: String
                switch try SATSolver.solve(formula) {
                case .satisfiable(let certificate):
                    try SATProofKernel.verify(formula: formula, certificate: certificate)
                    outcome = "satisfiable"
                case .unsatisfiable(let certificate):
                    try SATProofKernel.verify(formula: formula, certificate: certificate)
                    outcome = "unsatisfiable"
                }
                lines.append(["sat", left.name, right.name, outcome].joined(separator: "\t"))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
