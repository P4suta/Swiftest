namespace Swiftest

inductive LeaseObservation where
  | quiescent
  | attributeAmbiguous
  | mutation
  | unknownDescriptor
  | queueUnavailable
deriving DecidableEq, Repr

inductive LeaseContinuity where
  | eventFree
  | attributeAmbiguous
deriving DecidableEq, Repr

def leaseContinuityJoin : LeaseContinuity → LeaseContinuity → LeaseContinuity
  | .eventFree, .eventFree => .eventFree
  | .eventFree, .attributeAmbiguous => .attributeAmbiguous
  | .attributeAmbiguous, .eventFree => .attributeAmbiguous
  | .attributeAmbiguous, .attributeAmbiguous => .attributeAmbiguous

theorem leaseContinuityJoinAssociative
    (left middle right : LeaseContinuity) :
    leaseContinuityJoin (leaseContinuityJoin left middle) right =
      leaseContinuityJoin left (leaseContinuityJoin middle right) := by
  cases left <;> cases middle <;> cases right <;> rfl

theorem leaseContinuityJoinIdempotent (continuity : LeaseContinuity) :
    leaseContinuityJoin continuity continuity = continuity := by
  cases continuity <;> rfl

theorem leaseContinuityJoinCommutative (left right : LeaseContinuity) :
    leaseContinuityJoin left right = leaseContinuityJoin right left := by
  cases left <;> cases right <;> rfl

def maxFileEventGeneration : Nat := 18446744073709551615

def advanceFileEventGeneration (current : Nat) : Option Nat :=
  if current < maxFileEventGeneration then some (current + 1) else none

theorem advancedGenerationIsBoundedSuccessor
    (current next : Nat)
    (advanced : advanceFileEventGeneration current = some next) :
    next = current + 1 ∧ current < next ∧ next ≤ maxFileEventGeneration := by
  unfold advanceFileEventGeneration at advanced
  split at advanced
  · rename_i withinBound
    cases advanced
    exact ⟨rfl, Nat.lt_succ_self current, Nat.succ_le_of_lt withinBound⟩
  · simp at advanced

theorem advancedGenerationIsUnique
    (current first second : Nat)
    (firstAdvance : advanceFileEventGeneration current = some first)
    (secondAdvance : advanceFileEventGeneration current = some second) :
    first = second := by
  calc
    first = current + 1 := (advancedGenerationIsBoundedSuccessor current first firstAdvance).1
    _ = second := (advancedGenerationIsBoundedSuccessor current second secondAdvance).1.symm

theorem generationCannotWrapAtMaximum :
    advanceFileEventGeneration maxFileEventGeneration = none := by
  decide

theorem generationReachesMaximumWithoutWrap :
    advanceFileEventGeneration (maxFileEventGeneration - 1) =
      some maxFileEventGeneration := by
  decide

structure LeaseWitness where
  continuity : LeaseContinuity
  generation : Nat
deriving DecidableEq, Repr

def initialLeaseWitness : LeaseWitness := ⟨.eventFree, 0⟩

def witnessIncluding (witness : LeaseWitness) (continuity : LeaseContinuity) : LeaseWitness :=
  ⟨leaseContinuityJoin witness.continuity continuity, witness.generation⟩

def witnessRecordingAttribute (witness : LeaseWitness) : Option LeaseWitness :=
  match advanceFileEventGeneration witness.generation with
  | none => none
  | some next => some ⟨.attributeAmbiguous, next⟩

theorem witnessAttributeRecordAdvances
    (prior next : LeaseWitness)
    (recorded : witnessRecordingAttribute prior = some next) :
    next.continuity = .attributeAmbiguous ∧
      next.generation = prior.generation + 1 ∧
      prior.generation < next.generation ∧
      next.generation ≤ maxFileEventGeneration := by
  unfold witnessRecordingAttribute at recorded
  cases advanced : advanceFileEventGeneration prior.generation with
  | none => simp [advanced] at recorded
  | some generation =>
      have successor := advancedGenerationIsBoundedSuccessor
        prior.generation generation advanced
      simp [advanced] at recorded
      cases recorded
      exact ⟨rfl, successor.1, successor.2.1, successor.2.2⟩

theorem successiveAttributesHaveDistinctWitnesses
    (prior first second : LeaseWitness)
    (firstRecord : witnessRecordingAttribute prior = some first)
    (secondRecord : witnessRecordingAttribute first = some second) :
    first.continuity = second.continuity ∧
      first.generation < second.generation ∧ first ≠ second := by
  have firstProof := witnessAttributeRecordAdvances prior first firstRecord
  have secondProof := witnessAttributeRecordAdvances first second secondRecord
  refine ⟨firstProof.1.trans secondProof.1.symm, secondProof.2.2.1, ?_⟩
  intro sameWitness
  have sameGeneration : first.generation = second.generation :=
    congrArg LeaseWitness.generation sameWitness
  exact (Nat.ne_of_lt secondProof.2.2.1) sameGeneration

theorem continuityJoinDoesNotConsumeGeneration
    (witness : LeaseWitness) (continuity : LeaseContinuity) :
    (witnessIncluding witness continuity).generation = witness.generation := by
  rfl

def repeatedAttributeWitness : Nat → Option LeaseWitness
  | 0 => some initialLeaseWitness
  | count + 1 => (repeatedAttributeWitness count).bind witnessRecordingAttribute

theorem fourAttributesProduceFourthGeneration :
    repeatedAttributeWitness 4 = some ⟨.attributeAmbiguous, 4⟩ := by
  decide

structure LeaseHealth where
  witness : LeaseWitness
  firstPath : Option Nat
deriving DecidableEq, Repr

def initialLeaseHealth : LeaseHealth := ⟨initialLeaseWitness, none⟩

def healthIncluding (health : LeaseHealth) (continuity : LeaseContinuity) : LeaseHealth :=
  ⟨witnessIncluding health.witness continuity, health.firstPath⟩

def healthRecordingAttribute (health : LeaseHealth) (path : Nat) : Option LeaseHealth :=
  match witnessRecordingAttribute health.witness with
  | none => none
  | some witness =>
      let first := match health.firstPath with
        | none => some path
        | some previous => some previous
      some ⟨witness, first⟩

theorem healthIncludingRetainsFirstPath
    (health : LeaseHealth) (continuity : LeaseContinuity) :
    (healthIncluding health continuity).firstPath = health.firstPath := by
  rfl

theorem healthRecordRetainsFirstPath
    (prior next : LeaseHealth) (path first : Nat)
    (existing : prior.firstPath = some first)
    (recorded : healthRecordingAttribute prior path = some next) :
    next.firstPath = some first := by
  unfold healthRecordingAttribute at recorded
  cases advanced : witnessRecordingAttribute prior.witness with
  | none => simp [advanced] at recorded
  | some witness =>
      simp [advanced, existing] at recorded
      cases recorded
      rfl

theorem healthRecordAdvancesGeneration
    (prior next : LeaseHealth) (path : Nat)
    (recorded : healthRecordingAttribute prior path = some next) :
    next.witness.generation = prior.witness.generation + 1 := by
  unfold healthRecordingAttribute at recorded
  cases advanced : witnessRecordingAttribute prior.witness with
  | none => simp [advanced] at recorded
  | some witness =>
      simp [advanced] at recorded
      cases recorded
      exact (witnessAttributeRecordAdvances prior.witness witness advanced).2.1

theorem twoAttributesRetainFirstPath :
    ((healthRecordingAttribute initialLeaseHealth 1).bind
      (fun first => healthRecordingAttribute first 2)).map
      (fun second => second.firstPath) = some (some 1) := by
  decide

def leaseContinuityText : LeaseContinuity → String
  | .eventFree => "event-free"
  | .attributeAmbiguous => "attribute-ambiguous"

inductive LeaseTransition where
  | polling (remainingAttributes : Nat) (continuity : LeaseContinuity)
  | verified (continuity : LeaseContinuity)
  | invalid
deriving DecidableEq, Repr

def leaseAdvance : LeaseTransition → LeaseObservation → LeaseTransition
  | .polling _ continuity, .quiescent => .verified continuity
  | .polling 0 _, .attributeAmbiguous => .invalid
  | .polling (remaining + 1) continuity, .attributeAmbiguous =>
      .polling remaining (leaseContinuityJoin continuity .attributeAmbiguous)
  | .polling _ _, .mutation => .invalid
  | .polling _ _, .unknownDescriptor => .invalid
  | .polling _ _, .queueUnavailable => .invalid
  | .verified continuity, _ => .verified continuity
  | .invalid, _ => .invalid

def runLeaseTrace : LeaseTransition → List LeaseObservation → LeaseTransition
  | state, [] => state
  | state, event :: rest => runLeaseTrace (leaseAdvance state event) rest

theorem invalidAbsorbsObservation (event : LeaseObservation) :
    leaseAdvance .invalid event = .invalid := by
  rfl

theorem invalidAbsorbsTrace (events : List LeaseObservation) :
    runLeaseTrace .invalid events = .invalid := by
  induction events with
  | nil => rfl
  | cons event rest ih =>
      simpa [runLeaseTrace, invalidAbsorbsObservation] using ih

theorem mutationInvalidates
    (remaining : Nat) (continuity : LeaseContinuity) (rest : List LeaseObservation) :
    runLeaseTrace (.polling remaining continuity) (.mutation :: rest) = .invalid := by
  simpa [runLeaseTrace, leaseAdvance] using invalidAbsorbsTrace rest

theorem unknownDescriptorInvalidates
    (remaining : Nat) (continuity : LeaseContinuity) (rest : List LeaseObservation) :
    runLeaseTrace (.polling remaining continuity) (.unknownDescriptor :: rest) = .invalid := by
  simpa [runLeaseTrace, leaseAdvance] using invalidAbsorbsTrace rest

theorem queueErrorInvalidates
    (remaining : Nat) (continuity : LeaseContinuity) (rest : List LeaseObservation) :
    runLeaseTrace (.polling remaining continuity) (.queueUnavailable :: rest) = .invalid := by
  simpa [runLeaseTrace, leaseAdvance] using invalidAbsorbsTrace rest

def taintedOrInvalid : LeaseTransition → Bool
  | .polling _ .eventFree => false
  | .polling _ .attributeAmbiguous => true
  | .verified .eventFree => false
  | .verified .attributeAmbiguous => true
  | .invalid => true

theorem ambiguousOrInvalidRemainsSo
    (state : LeaseTransition) (event : LeaseObservation)
    (tainted : taintedOrInvalid state = true) :
    taintedOrInvalid (leaseAdvance state event) = true := by
  cases state with
  | polling remaining continuity =>
      cases continuity with
      | eventFree => simp [taintedOrInvalid] at tainted
      | attributeAmbiguous =>
          cases remaining with
          | zero => cases event <;> rfl
          | succ remaining => cases event <;> rfl
  | verified continuity =>
      cases continuity with
      | eventFree => simp [taintedOrInvalid] at tainted
      | attributeAmbiguous => cases event <;> rfl
  | invalid => cases event <;> rfl

theorem ambiguousOrInvalidTraceRemainsSo
    (state : LeaseTransition) (events : List LeaseObservation)
    (tainted : taintedOrInvalid state = true) :
    taintedOrInvalid (runLeaseTrace state events) = true := by
  induction events generalizing state with
  | nil => simpa [runLeaseTrace] using tainted
  | cons event rest ih =>
      exact ih (leaseAdvance state event) (ambiguousOrInvalidRemainsSo state event tainted)

theorem ambiguousCannotVerifyEventFree
    (remaining : Nat) (events : List LeaseObservation) :
    runLeaseTrace (.polling remaining .attributeAmbiguous) events ≠ .verified .eventFree := by
  intro verified
  have tainted := ambiguousOrInvalidTraceRemainsSo
    (.polling remaining .attributeAmbiguous) events (by rfl)
  simp [verified, taintedOrInvalid] at tainted

theorem onlyAmbiguousAttributeCanContinue
    (remaining next : Nat) (continuity nextContinuity : LeaseContinuity)
    (event : LeaseObservation)
    (continued : leaseAdvance (.polling remaining continuity) event =
      .polling next nextContinuity) :
    event = .attributeAmbiguous := by
  cases event <;> cases remaining <;> simp [leaseAdvance] at continued ⊢

def boundedLeaseDrain : Nat → LeaseTransition → (Nat → LeaseObservation) → Nat →
    LeaseTransition × Nat
  | 0, .polling _ _, _, _ => (.invalid, 0)
  | 0, .verified continuity, _, _ => (.verified continuity, 0)
  | 0, .invalid, _, _ => (.invalid, 0)
  | fuel + 1, .polling remaining continuity, poll, index =>
      let result := boundedLeaseDrain fuel
        (leaseAdvance (.polling remaining continuity) (poll index)) poll (index + 1)
      (result.1, result.2 + 1)
  | _ + 1, .verified continuity, _, _ => (.verified continuity, 0)
  | _ + 1, .invalid, _, _ => (.invalid, 0)

def leaseTerminal : LeaseTransition → Bool
  | .polling _ _ => false
  | .verified _ => true
  | .invalid => true

theorem boundedLeaseDrainCloses
    (fuel : Nat) (state : LeaseTransition) (poll : Nat → LeaseObservation) (index : Nat) :
    leaseTerminal (boundedLeaseDrain fuel state poll index).1 = true := by
  induction fuel generalizing state index with
  | zero => cases state <;> rfl
  | succ fuel ih =>
      cases state with
      | polling remaining continuity =>
          simpa [boundedLeaseDrain] using
            ih (leaseAdvance (.polling remaining continuity) (poll index)) (index + 1)
      | verified continuity => rfl
      | invalid => rfl

theorem boundedLeaseDrainPollCount
    (fuel : Nat) (state : LeaseTransition) (poll : Nat → LeaseObservation) (index : Nat) :
    (boundedLeaseDrain fuel state poll index).2 ≤ fuel := by
  induction fuel generalizing state index with
  | zero =>
      cases state <;> simp [boundedLeaseDrain]
  | succ fuel ih =>
      cases state with
      | polling remaining continuity =>
          simpa [boundedLeaseDrain, Nat.add_comm] using
            Nat.succ_le_succ
              (ih (leaseAdvance (.polling remaining continuity) (poll index)) (index + 1))
      | verified continuity => simp [boundedLeaseDrain]
      | invalid => simp [boundedLeaseDrain]

def boundedLeaseVerification
    (registrationCount : Nat) (poll : Nat → LeaseObservation) : LeaseTransition × Nat :=
  boundedLeaseDrain (registrationCount * 4 + 1)
    (.polling (registrationCount * 4) .eventFree) poll 0

theorem boundedLeaseVerificationPollCount
    (registrationCount : Nat) (poll : Nat → LeaseObservation) :
    (boundedLeaseVerification registrationCount poll).2 ≤ registrationCount * 4 + 1 := by
  exact boundedLeaseDrainPollCount _ _ _ _

theorem boundedLeaseVerificationCloses
    (registrationCount : Nat) (poll : Nat → LeaseObservation) :
    leaseTerminal (boundedLeaseVerification registrationCount poll).1 = true := by
  exact boundedLeaseDrainCloses _ _ _ _

def leaseTransitionText : LeaseTransition → String
  | .polling _ .eventFree => "polling-event-free"
  | .polling _ .attributeAmbiguous => "polling-attribute-ambiguous"
  | .verified .eventFree => "verified-event-free"
  | .verified .attributeAmbiguous => "verified-attribute-ambiguous"
  | .invalid => "invalid"

def leaseBoundaryOracleCases : List (String × Nat × List LeaseObservation) := [
  ("empty-trace", 1, []),
  ("quiet", 1, [.quiescent]),
  ("mutation", 1, [.mutation, .quiescent]),
  ("unknown", 1, [.unknownDescriptor, .quiescent]),
  ("queue-error", 1, [.queueUnavailable, .quiescent]),
  ("attribute", 1, [.attributeAmbiguous]),
  ("attribute-quiet", 1, [.attributeAmbiguous, .quiescent]),
  ("attribute-mutation", 1, [.attributeAmbiguous, .mutation, .quiescent]),
  ("attribute-unknown", 1, [.attributeAmbiguous, .unknownDescriptor, .quiescent]),
  ("attribute-queue-error", 1, [.attributeAmbiguous, .queueUnavailable, .quiescent]),
  ("four-attributes", 1, [
    .attributeAmbiguous, .attributeAmbiguous, .attributeAmbiguous, .attributeAmbiguous,
    .quiescent
  ]),
  ("five-attributes", 1, [
    .attributeAmbiguous, .attributeAmbiguous, .attributeAmbiguous, .attributeAmbiguous,
    .attributeAmbiguous, .quiescent
  ]),
  ("larger-inventory", 2, [
    .attributeAmbiguous, .attributeAmbiguous, .attributeAmbiguous, .attributeAmbiguous,
    .attributeAmbiguous, .quiescent
  ]),
  ("quiet-then-mutation", 1, [.quiescent, .mutation]),
  ("attribute-then-quiet-then-mutation", 1, [
    .attributeAmbiguous, .quiescent, .mutation
  ])
]

def leaseObservationCases : List (String × LeaseObservation) := [
  ("quiet", .quiescent),
  ("attribute", .attributeAmbiguous),
  ("mutation", .mutation),
  ("unknown", .unknownDescriptor),
  ("queue-error", .queueUnavailable)
]

def leaseTraceGrid : Nat → List (String × List LeaseObservation)
  | 0 => [("none", [])]
  | depth + 1 =>
      ("none", []) :: leaseObservationCases.flatMap fun head =>
        (leaseTraceGrid depth).map fun tail =>
          let name := if tail.1 == "none" then head.1 else head.1 ++ "-" ++ tail.1
          (name, head.2 :: tail.2)

def leaseOracleCases : List (String × Nat × List LeaseObservation) :=
  leaseBoundaryOracleCases ++ ([1, 2] : List Nat).flatMap fun count =>
    (leaseTraceGrid 3).map fun trace =>
      ("grid-" ++ toString count ++ "-" ++ trace.1, count, trace.2)

end Swiftest
