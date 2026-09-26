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
  | .provenIrrelevant => true
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

end Swiftest
