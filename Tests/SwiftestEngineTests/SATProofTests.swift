@testable import SwiftestSolver
import Testing

@Test
func unsatisfiableResultRequiresIndependentExhaustiveVerification() throws {
    let variable = try SATVariable.make(1)
    let formula = SATFormula(clauses: [
        try SATClause.make([.positive(variable)]),
        try SATClause.make([.negative(variable)]),
    ])
    let result = try SATSolver.solve(formula)
    switch result {
    case .satisfiable(let certificate):
        Issue.record("contradictory formula was satisfiable")
        #expect(certificate.assignments.isEmpty)
    case .unsatisfiable(let certificate):
        #expect(certificate.verificationDomainSize.rawValue == 2)
        try SATProofKernel.verify(formula: formula, certificate: certificate)
        let satisfiable = SATFormula(clauses: [try SATClause.make([.positive(variable)])])
        do {
            try SATProofKernel.verify(formula: satisfiable, certificate: certificate)
            Issue.record("satisfiable formula passed the independent kernel")
        } catch let error {
            #expect(error == .invalidCertificate)
        }
    }
}

@Test
func independentKernelChecksEveryTwoUnitClauseFormula() throws {
    let first = try SATVariable.make(1)
    let second = try SATVariable.make(2)
    let literals: [SATLiteral] = [
        .positive(first), .negative(first), .positive(second), .negative(second),
    ]
    var satisfiable = 0
    var unsatisfiable = 0
    for left in literals {
        for right in literals {
            let formula = SATFormula(clauses: [
                try SATClause.make([left]),
                try SATClause.make([right]),
            ])
            switch try SATSolver.solve(formula) {
            case .satisfiable(let certificate):
                try SATProofKernel.verify(formula: formula, certificate: certificate)
                satisfiable += 1
            case .unsatisfiable(let certificate):
                try SATProofKernel.verify(formula: formula, certificate: certificate)
                unsatisfiable += 1
            }
        }
    }
    #expect(satisfiable == 12)
    #expect(unsatisfiable == 4)
}

@Test
func solverCompletesIrrelevantVariablesDeterministically() throws {
    let first = try SATVariable.make(1)
    let second = try SATVariable.make(2)
    let formula = SATFormula(clauses: [
        try SATClause.make([.positive(first)]),
        try SATClause.make([.positive(first), .positive(second)]),
    ])
    switch try SATSolver.solve(formula) {
    case .satisfiable(let certificate):
        try SATProofKernel.verify(formula: formula, certificate: certificate)
        #expect(certificate.assignments[first] == .trueValue)
        #expect(certificate.assignments[second] == .falseValue)
    case .unsatisfiable:
        Issue.record("satisfiable formula was rejected")
    }
}

@Test
func satOracleEnumeratesTheClosedTwoVariableDomain() throws {
    let lines = try SATOracle.text().split(separator: "\n")
    #expect(lines.count == 16)
    #expect(lines.first == "sat\tx\tx\tsatisfiable")
    #expect(lines.last == "sat\tnot-y\tnot-y\tsatisfiable")
    #expect(lines.filter { $0.hasSuffix("unsatisfiable") }.count == 4)
}

@Test
func independentKernelRejectsInjectedAssignmentFault() throws {
    let variable = try SATVariable.make(1)
    let formula = SATFormula(clauses: [try SATClause.make([.positive(variable)])])
    let defective = SATCertificate(assignments: [variable: .falseValue])
    do {
        try SATProofKernel.verify(formula: formula, certificate: defective)
        Issue.record("defective assignment passed the independent kernel")
    } catch let error {
        #expect(error == .invalidCertificate)
    }
}

@Test
func independentKernelRejectsInjectedDomainSizeFault() throws {
    let variable = try SATVariable.make(1)
    let formula = SATFormula(clauses: [
        try SATClause.make([.positive(variable)]),
        try SATClause.make([.negative(variable)]),
    ])
    let defective = UnsatisfiableCertificate(
        verificationDomainSize: try .nonnegative(1)
    )
    do {
        try SATProofKernel.verify(formula: formula, certificate: defective)
        Issue.record("defective exhaustive domain size passed the independent kernel")
    } catch let error {
        #expect(error == .invalidCertificate)
    }
}
