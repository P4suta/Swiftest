namespace Swiftest

inductive WorldDisposition where
  | executed
  | provenIrrelevant
deriving DecidableEq, Repr

structure WorldClosure (World : Type) where
  worlds : List World
  disposition : World → WorldDisposition
  closed : ∀ world, world ∈ worlds →
    disposition world = .executed ∨ disposition world = .provenIrrelevant

theorem noWorldOmitted
    {World : Type}
    (closure : WorldClosure World)
    (world : World)
    (declared : world ∈ closure.worlds) :
    closure.disposition world = .executed ∨
      closure.disposition world = .provenIrrelevant := by
  exact closure.closed world declared

def cartesian : List (List α) → List (List α)
  | [] => [[]]
  | axis :: axes => axis.flatMap fun value =>
      (cartesian axes).map fun suffix => value :: suffix

theorem cartesianEmpty : cartesian ([] : List (List α)) = [[]] := by
  rfl

theorem cartesianConsLength (axis : List α) (axes : List (List α)) :
    (cartesian (axis :: axes)).length = axis.length * (cartesian axes).length := by
  have mappedSum : ∀ values : List α,
      (values.map fun _ => (cartesian axes).length).sum =
        values.length * (cartesian axes).length := by
    intro values
    induction values with
    | nil => simp
    | cons value rest inductionHypothesis =>
        simp [inductionHypothesis, Nat.add_mul, Nat.add_comm]
  simp [cartesian, List.length_flatMap, mappedSum]

end Swiftest
