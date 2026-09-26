namespace Swiftest

inductive Signal where
  | absent
  | present
deriving DecidableEq, Repr

inductive Scope where
  | complete
  | change
  | scoped
deriving DecidableEq, Repr

inductive Verdict where
  | assured
  | changeAssured
  | scopeAssured
  | unsettled
  | gaps
  | gapsAndUnsettled
  | invalid
deriving DecidableEq, Repr

def verdict (apparatus gap unsettled : Signal) (scope : Scope) : Verdict :=
  match apparatus, gap, unsettled, scope with
  | .present, _, _, _ => .invalid
  | .absent, .present, .present, _ => .gapsAndUnsettled
  | .absent, .present, .absent, _ => .gaps
  | .absent, .absent, .present, _ => .unsettled
  | .absent, .absent, .absent, .complete => .assured
  | .absent, .absent, .absent, .change => .changeAssured
  | .absent, .absent, .absent, .scoped => .scopeAssured

theorem apparatusPriority (gap unsettled : Signal) (scope : Scope) :
    verdict .present gap unsettled scope = .invalid := by
  rfl

theorem combinedPriority (scope : Scope) :
    verdict .absent .present .present scope = .gapsAndUnsettled := by
  rfl

theorem scoreInvariant
    (apparatus gap unsettled : Signal)
    (scope : Scope)
    (_firstScore _secondScore : Nat) :
    verdict apparatus gap unsettled scope = verdict apparatus gap unsettled scope := by
  rfl

theorem proofModeInvariant
    (apparatus gap unsettled : Signal)
    (scope : Scope)
    (_proofEnabled : Bool) :
    verdict apparatus gap unsettled scope = verdict apparatus gap unsettled scope := by
  rfl

theorem executionCountInvariant
    (apparatus gap unsettled : Signal)
    (scope : Scope)
    (_firstCount _secondCount : Nat) :
    verdict apparatus gap unsettled scope = verdict apparatus gap unsettled scope := by
  rfl

end Swiftest
