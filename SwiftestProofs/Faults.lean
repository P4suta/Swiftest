import SwiftestProofs.Verdict

namespace Swiftest

inductive FaultDomain where
  | process
  | filesystem
  | codec
  | store
  | network
  | clock
  | randomness
  | device
  | cancellation
  | scheduler
  | testRunner
deriving DecidableEq, Repr

structure FaultPoint where
  identifier : Nat
  domain : FaultDomain
deriving DecidableEq, Repr

structure CompoundFault where
  identifier : Nat
  points : List FaultPoint
deriving DecidableEq, Repr

structure FaultCampaign where
  points : List FaultPoint
  pointIdentifiersUnique : (points.map FaultPoint.identifier).Nodup
  compounds : List CompoundFault
  compoundIdentifiersUnique : (compounds.map CompoundFault.identifier).Nodup

inductive FaultScenario where
  | clean
  | single (point : FaultPoint)
  | compound (fault : CompoundFault)
deriving DecidableEq, Repr

def faultScenarios (campaign : FaultCampaign) : List FaultScenario :=
  .clean :: campaign.points.map .single ++ campaign.compounds.map .compound

theorem cleanScenarioIncluded (campaign : FaultCampaign) :
    .clean ∈ faultScenarios campaign := by
  simp [faultScenarios]

theorem everySingleFaultIncluded
    (campaign : FaultCampaign)
    (point : FaultPoint)
    (declared : point ∈ campaign.points) :
    .single point ∈ faultScenarios campaign := by
  simp [faultScenarios, declared]

theorem everyCompoundFaultIncluded
    (campaign : FaultCampaign)
    (compound : CompoundFault)
    (declared : compound ∈ campaign.compounds) :
    .compound compound ∈ faultScenarios campaign := by
  simp [faultScenarios, declared]

theorem exhaustiveScenarioCount (campaign : FaultCampaign) :
    (faultScenarios campaign).length =
      1 + campaign.points.length + campaign.compounds.length := by
  simp [faultScenarios, Nat.add_comm, Nat.add_assoc]

def standardPointCount : Nat := 22

def standardCompoundSizes : List Nat := [2, 2, 2, 2, 2, 2]

theorem standardScenarioCount :
    1 + standardPointCount + standardCompoundSizes.length = 29 := by
  decide

theorem standardInjectedActivationCount :
    standardPointCount + standardCompoundSizes.sum = 34 := by
  decide

inductive FaultResult where
  | recovered
  | failedClosed
  | provenIrrelevant
  | unreached
  | uncontrolled
  | undetected
deriving DecidableEq, Repr

def acceptedFaultResult : FaultResult → Bool
  | .recovered => true
  | .failedClosed => true
  | .provenIrrelevant => false
  | .unreached => false
  | .uncontrolled => false
  | .undetected => false

def faultResultText : FaultResult → String
  | .recovered => "recovered"
  | .failedClosed => "failed-closed"
  | .provenIrrelevant => "proven-irrelevant"
  | .unreached => "unreached"
  | .uncontrolled => "uncontrolled"
  | .undetected => "undetected"

def faultResults : List FaultResult := [
  .recovered,
  .failedClosed,
  .provenIrrelevant,
  .unreached,
  .uncontrolled,
  .undetected
]

structure FaultCertificate (campaign : FaultCampaign) where
  result : FaultScenario → FaultResult
  closesEveryScenario : ∀ scenario, scenario ∈ faultScenarios campaign →
    acceptedFaultResult (result scenario) = true

theorem everyFaultScenarioAudited
    (campaign : FaultCampaign)
    (certificate : FaultCertificate campaign)
    (scenario : FaultScenario)
    (declared : scenario ∈ faultScenarios campaign) :
    acceptedFaultResult (certificate.result scenario) = true := by
  exact certificate.closesEveryScenario scenario declared

theorem unreachedFaultRejected : acceptedFaultResult .unreached = false := by
  rfl

theorem uncontrolledFaultRejected : acceptedFaultResult .uncontrolled = false := by
  rfl

theorem undetectedFaultRejected : acceptedFaultResult .undetected = false := by
  rfl

theorem digestOnlyIrrelevanceRejected :
    acceptedFaultResult .provenIrrelevant = false := by
  rfl

inductive FaultEvidenceState where
  | verified
  | structural
  | unverified
deriving DecidableEq, Repr

def reportVerdict (base : Verdict) (faults : FaultEvidenceState) : Verdict :=
  match faults, base with
  | .verified, base => base
  | .structural, .assured => .gaps
  | .structural, .changeAssured => .gaps
  | .structural, .scopeAssured => .gaps
  | .structural, .gaps => .gaps
  | .structural, .unsettled => .gapsAndUnsettled
  | .structural, .gapsAndUnsettled => .gapsAndUnsettled
  | .structural, .invalid => .invalid
  | .unverified, .assured => .gaps
  | .unverified, .changeAssured => .gaps
  | .unverified, .scopeAssured => .gaps
  | .unverified, .gaps => .gaps
  | .unverified, .unsettled => .gapsAndUnsettled
  | .unverified, .gapsAndUnsettled => .gapsAndUnsettled
  | .unverified, .invalid => .invalid

theorem unverifiedCompleteCannotBeAssured :
    reportVerdict .assured .unverified = .gaps := by
  rfl

theorem unverifiedChangeCannotBeAssured :
    reportVerdict .changeAssured .unverified = .gaps := by
  rfl

theorem unverifiedScopeCannotBeAssured :
    reportVerdict .scopeAssured .unverified = .gaps := by
  rfl

theorem unverifiedUnsettledRetainsUnsettled :
    reportVerdict .unsettled .unverified = .gapsAndUnsettled := by
  rfl

theorem unverifiedApparatusRemainsInvalid :
    reportVerdict .invalid .unverified = .invalid := by
  rfl

theorem verifiedFaultsPreserveBaseVerdict (base : Verdict) :
    reportVerdict base .verified = base := by
  rfl

def isAssuredVerdict : Verdict → Bool
  | .assured => true
  | .changeAssured => true
  | .scopeAssured => true
  | .unsettled => false
  | .gaps => false
  | .gapsAndUnsettled => false
  | .invalid => false

theorem noUnverifiedFaultCampaignCanBeAssured (base : Verdict) :
    isAssuredVerdict (reportVerdict base .unverified) = false := by
  cases base <;> rfl

theorem noStructuralFaultCampaignCanBeAssured (base : Verdict) :
    isAssuredVerdict (reportVerdict base .structural) = false := by
  cases base <;> rfl

inductive ExecutedFaultResult where
  | apparatusFailed
  | observed (result : FaultResult)
deriving DecidableEq, Repr

def recordBoundaryResult (reached : Bool) (reported : Option FaultResult) :
    ExecutedFaultResult :=
  match reached, reported with
  | false, none => .observed .unreached
  | false, some _ => .apparatusFailed
  | true, none => .observed .uncontrolled
  | true, some result => .observed result

def acceptedExecutedResult : ExecutedFaultResult → Bool
  | .apparatusFailed => false
  | .observed result => acceptedFaultResult result

theorem unactivatedClaimRejected (result : FaultResult) :
    acceptedExecutedResult (recordBoundaryResult false (some result)) = false := by
  rfl

theorem unreachedBoundaryRejected :
    acceptedExecutedResult (recordBoundaryResult false none) = false := by
  rfl

theorem missingHandlingRejected :
    acceptedExecutedResult (recordBoundaryResult true none) = false := by
  rfl

theorem acceptedExecutionReached
    (reached : Bool)
    (reported : Option FaultResult)
    (accepted : acceptedExecutedResult (recordBoundaryResult reached reported) = true) :
    reached = true := by
  cases reached <;> cases reported <;> simp [recordBoundaryResult, acceptedExecutedResult,
    acceptedFaultResult] at accepted ⊢

theorem acceptedExecutionHasHandling
    (reached : Bool)
    (reported : Option FaultResult)
    (accepted : acceptedExecutedResult (recordBoundaryResult reached reported) = true) :
    reported.isSome = true := by
  cases reached <;> cases reported <;> simp [recordBoundaryResult, acceptedExecutedResult,
    acceptedFaultResult] at accepted ⊢

def closeBoundaryTrace
    (declared : List Nat)
    (reached : Nat → Bool)
    (reported : Nat → Option FaultResult) : Bool :=
  declared.all fun point =>
    acceptedExecutedResult (recordBoundaryResult (reached point) (reported point))

def cleanControlVisitedEveryBoundary
    (declared : List Nat)
    (visited : Nat → Bool) : Bool :=
  declared.all visited

theorem acceptedCleanControlVisitedEveryBoundary
    (declared : List Nat)
    (visited : Nat → Bool)
    (accepted : cleanControlVisitedEveryBoundary declared visited = true)
    (point : Nat)
    (member : point ∈ declared) :
    visited point = true := by
  exact (List.all_eq_true.mp accepted) point member

def closeSealedBoundaryTrace
    (declared attested : List FaultPoint)
    (reached : Nat → Bool)
    (reported : Nat → Option FaultResult) : Bool :=
  if declared == attested then
    closeBoundaryTrace (declared.map FaultPoint.identifier) reached reported
  else false

theorem alteredFaultDeclarationRejected
    (declared attested : List FaultPoint)
    (reached : Nat → Bool)
    (reported : Nat → Option FaultResult)
    (changed : declared ≠ attested) :
    closeSealedBoundaryTrace declared attested reached reported = false := by
  simp [closeSealedBoundaryTrace, changed]

theorem closedBoundaryTraceRequiresEveryPointReached
    (declared : List Nat)
    (reached : Nat → Bool)
    (reported : Nat → Option FaultResult)
    (closed : closeBoundaryTrace declared reached reported = true)
    (point : Nat)
    (member : point ∈ declared) :
    reached point = true := by
  have accepted : acceptedExecutedResult
      (recordBoundaryResult (reached point) (reported point)) = true := by
    exact (List.all_eq_true.mp closed) point member
  exact acceptedExecutionReached (reached point) (reported point) accepted

theorem closedBoundaryTraceRequiresEveryPointHandled
    (declared : List Nat)
    (reached : Nat → Bool)
    (reported : Nat → Option FaultResult)
    (closed : closeBoundaryTrace declared reached reported = true)
    (point : Nat)
    (member : point ∈ declared) :
    (reported point).isSome = true := by
  have accepted : acceptedExecutedResult
      (recordBoundaryResult (reached point) (reported point)) = true := by
    exact (List.all_eq_true.mp closed) point member
  exact acceptedExecutionHasHandling (reached point) (reported point) accepted

theorem emptyBoundaryTraceCannotProveNonemptyCampaign
    (point : Nat)
    (reached : Nat → Bool)
    (reported : Nat → Option FaultResult)
    (notReached : reached point = false) :
    closeBoundaryTrace [point] reached reported = false := by
  cases h : reported point <;>
    simp [closeBoundaryTrace, notReached, h, recordBoundaryResult,
      acceptedExecutedResult, acceptedFaultResult]

end Swiftest
