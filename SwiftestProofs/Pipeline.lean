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

inductive PipelineStep : PipelineState → PipelineState → Prop where
  | discoverPlan : PipelineStep .discovered .planned
  | planFreeze : PipelineStep .planned .frozen
  | freezeBuild : PipelineStep .frozen .built
  | buildBaseline : PipelineStep .built .baselinePassed
  | baselineExecute : PipelineStep .baselinePassed .executed
  | executeRecord : PipelineStep .executed .recorded
  | recordAudit : PipelineStep .recorded .audited

theorem pipelineStepIncreases {before after : PipelineState}
    (step : PipelineStep before after) : before.rank < after.rank := by
  cases step <;> decide

theorem pipelineStepNeverReverses {before after : PipelineState}
    (step : PipelineStep before after) : ¬after.rank ≤ before.rank := by
  exact Nat.not_le_of_gt (pipelineStepIncreases step)

end Swiftest
