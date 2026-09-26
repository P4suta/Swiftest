namespace Swiftest

structure Literal where
  index : Nat
  positive : Bool
deriving DecidableEq, Repr

abbrev Assignment := Nat → Bool
abbrev Clause := List Literal
abbrev Formula := List Clause

def evalLiteral (assignment : Assignment) (literal : Literal) : Bool :=
  if literal.positive then assignment literal.index else !(assignment literal.index)

def evalClause (assignment : Assignment) (clause : Clause) : Bool :=
  clause.any (evalLiteral assignment)

def verifySAT (formula : Formula) (assignment : Assignment) : Bool :=
  formula.all (evalClause assignment)

def Satisfies (formula : Formula) (assignment : Assignment) : Prop :=
  ∀ clause ∈ formula, ∃ literal ∈ clause, evalLiteral assignment literal = true

theorem verifySATCorrect (formula : Formula) (assignment : Assignment) :
    verifySAT formula assignment = true ↔ Satisfies formula assignment := by
  simp [verifySAT, Satisfies, evalClause, List.all_eq_true, List.any_eq_true]

theorem verifiedCertificateSound
    (formula : Formula)
    (assignment : Assignment)
    (verified : verifySAT formula assignment = true) :
    Satisfies formula assignment := by
  exact (verifySATCorrect formula assignment).mp verified

theorem rejectedCertificateNotAccepted
    (formula : Formula)
    (assignment : Assignment)
    (rejected : verifySAT formula assignment = false) :
    ¬Satisfies formula assignment := by
  intro accepted
  have verified := (verifySATCorrect formula assignment).mpr accepted
  simp [rejected] at verified

end Swiftest
