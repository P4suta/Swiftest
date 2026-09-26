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
  verifySAT formula assignment = true

theorem verifiedCertificateSound
    (formula : Formula)
    (assignment : Assignment)
    (verified : verifySAT formula assignment = true) :
    Satisfies formula assignment := by
  exact verified

theorem rejectedCertificateNotAccepted
    (formula : Formula)
    (assignment : Assignment)
    (rejected : verifySAT formula assignment = false) :
    ¬Satisfies formula assignment := by
  intro accepted
  simp [Satisfies, rejected] at accepted

end Swiftest
