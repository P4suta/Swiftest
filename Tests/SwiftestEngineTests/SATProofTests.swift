import SwiftestSolver
import Testing

@Test
func unsatisfiableCountCannotPassIndependentProofKernel() throws {
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
        #expect(certificate.checkedAssignments.rawValue > 0)
        do {
            try SATProofKernel.verify(formula: formula, certificate: certificate)
            Issue.record("count-only unsatisfiable certificate was accepted")
        } catch let error {
            #expect(error == .unsatisfiableProofUnavailable)
        }
    }
}
