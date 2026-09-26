namespace Swiftest

def shrinkMeasureDecreases (current candidate : Nat) : Bool :=
  candidate < current

theorem selfCycleCannotShrink (measure : Nat) :
    shrinkMeasureDecreases measure measure = false := by
  simp [shrinkMeasureDecreases]

theorem increasingCandidateCannotShrink
    (current candidate : Nat)
    (increases : current ≤ candidate) :
    shrinkMeasureDecreases current candidate = false := by
  simp [shrinkMeasureDecreases, Nat.not_lt.mpr increases]

theorem strictShrinkRelationWellFounded :
    WellFounded (fun candidate current : Nat => candidate < current) := by
  exact Nat.lt_wfRel.wf

end Swiftest
