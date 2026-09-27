namespace Swiftest

inductive PipelineState where
  | discovered
  | planned
  | frozen
  | built
  | baselinePassed
  | executed
  | recorded
  | audited
deriving DecidableEq, Repr

def PipelineState.rank : PipelineState → Nat
  | .discovered => 0
  | .planned => 1
  | .frozen => 2
  | .built => 3
  | .baselinePassed => 4
  | .executed => 5
  | .recorded => 6
  | .audited => 7

inductive ReceiptKind where
  | build
  | baseline
  | execution
deriving DecidableEq, Repr

def PipelineState.requiredReceipt : PipelineState → Option ReceiptKind
  | .built => some .build
  | .baselinePassed => some .baseline
  | .executed => some .execution
  | .discovered | .planned | .frozen | .recorded | .audited => none

inductive PipelineStep : PipelineState → Option ReceiptKind → PipelineState → Prop where
  | discoverPlan : PipelineStep .discovered none .planned
  | planFreeze : PipelineStep .planned none .frozen
  | freezeBuild : PipelineStep .frozen (some .build) .built
  | buildBaseline : PipelineStep .built (some .baseline) .baselinePassed
  | baselineExecute : PipelineStep .baselinePassed (some .execution) .executed
  | executeRecord : PipelineStep .executed none .recorded
  | recordAudit : PipelineStep .recorded none .audited

theorem pipelineStepIncreases {before after : PipelineState} {receipt : Option ReceiptKind}
    (step : PipelineStep before receipt after) : before.rank < after.rank := by
  cases step <;> decide

theorem pipelineStepNeverReverses {before after : PipelineState} {receipt : Option ReceiptKind}
    (step : PipelineStep before receipt after) : ¬after.rank ≤ before.rank := by
  exact Nat.not_le_of_gt (pipelineStepIncreases step)

theorem pipelineStepRequiresMatchingReceipt {before after : PipelineState}
    {receipt : Option ReceiptKind}
    (step : PipelineStep before receipt after) : receipt = after.requiredReceipt := by
  cases step <;> rfl

theorem pipelineStepWithoutReceiptCannotReachGatedStage {before after : PipelineState}
    (step : PipelineStep before none after) :
    after ≠ .built ∧ after ≠ .baselinePassed ∧ after ≠ .executed := by
  cases step <;> decide

end Swiftest
