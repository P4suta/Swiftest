namespace Swiftest

inductive MutationStatus where
  | passed
  | failed
  | provenIrrelevant
deriving DecidableEq, Repr

structure MutationEvidence (Mutant World : Type) where
  mutant : Mutant
  world : World
  reached : MutationStatus
  infected : MutationStatus
  detected : MutationStatus

def MutationEvidence.point (observation : MutationEvidence Mutant World) : Mutant × World :=
  (observation.mutant, observation.world)

def mutationSuccess (observation : MutationEvidence Mutant World) : Bool :=
  decide (observation.reached = .passed) &&
    decide (observation.infected = .passed) &&
    decide (observation.detected = .passed)

theorem mutationSuccessIff (observation : MutationEvidence Mutant World) :
    mutationSuccess observation = true ↔
      observation.reached = .passed ∧
      observation.infected = .passed ∧
      observation.detected = .passed := by
  simp [mutationSuccess, and_assoc]

structure MutationGrid (Mutant World : Type) where
  mutants : List Mutant
  worlds : List World
  observed : List (MutationEvidence Mutant World)

def MutationGrid.observedPairs (grid : MutationGrid Mutant World) : List (Mutant × World) :=
  grid.observed.map MutationEvidence.point

def mutationGridPassed [DecidableEq Mutant] [DecidableEq World]
    (grid : MutationGrid Mutant World) : Bool :=
  decide grid.mutants.Nodup &&
    decide grid.worlds.Nodup &&
    decide grid.observedPairs.Nodup &&
    grid.observed.all (fun observation =>
      decide (observation.mutant ∈ grid.mutants ∧ observation.world ∈ grid.worlds)) &&
    grid.mutants.all (fun mutant =>
      grid.worlds.all (fun world => decide ((mutant, world) ∈ grid.observedPairs)))

theorem mutationGridUniqueDeclarations
    [DecidableEq Mutant] [DecidableEq World]
    (grid : MutationGrid Mutant World)
    (passed : mutationGridPassed grid = true) :
    grid.mutants.Nodup ∧ grid.worlds.Nodup := by
  simp only [mutationGridPassed, Bool.and_eq_true, decide_eq_true_eq] at passed
  exact passed.1.1.1

theorem mutationGridNoDuplicateDeclaredPair
    [DecidableEq Mutant] [DecidableEq World]
    (grid : MutationGrid Mutant World)
    (passed : mutationGridPassed grid = true)
    (first second : Nat)
    (firstBound : first < grid.observedPairs.length)
    (secondBound : second < grid.observedPairs.length)
    (samePair : grid.observedPairs[first] = grid.observedPairs[second]) :
    first = second := by
  have unique : grid.observedPairs.Nodup := by
    simp only [mutationGridPassed, Bool.and_eq_true, decide_eq_true_eq] at passed
    exact passed.1.1.2
  exact unique.eq_of_getElem_eq firstBound secondBound samePair

theorem mutationGridNoMissingDeclaredPair
    [DecidableEq Mutant] [DecidableEq World]
    (grid : MutationGrid Mutant World)
    (passed : mutationGridPassed grid = true)
    (mutant : Mutant)
    (world : World)
    (declaredMutant : mutant ∈ grid.mutants)
    (declaredWorld : world ∈ grid.worlds) :
    (mutant, world) ∈ grid.observedPairs := by
  have covered : grid.mutants.all (fun candidate =>
      grid.worlds.all (fun candidateWorld =>
        decide ((candidate, candidateWorld) ∈ grid.observedPairs))) = true := by
    simp only [mutationGridPassed, Bool.and_eq_true] at passed
    exact passed.2
  have mutantCovered := (List.all_eq_true.mp covered) mutant declaredMutant
  have worldCovered := (List.all_eq_true.mp mutantCovered) world declaredWorld
  exact of_decide_eq_true worldCovered

theorem mutationGridNoUnknownPair
    [DecidableEq Mutant] [DecidableEq World]
    (grid : MutationGrid Mutant World)
    (passed : mutationGridPassed grid = true)
    (observation : MutationEvidence Mutant World)
    (observed : observation ∈ grid.observed) :
    observation.mutant ∈ grid.mutants ∧ observation.world ∈ grid.worlds := by
  have declared : grid.observed.all (fun candidate =>
      decide (candidate.mutant ∈ grid.mutants ∧ candidate.world ∈ grid.worlds)) = true := by
    simp only [mutationGridPassed, Bool.and_eq_true] at passed
    exact passed.1.2
  exact of_decide_eq_true ((List.all_eq_true.mp declared) observation observed)

theorem mutationGridExactlyOneDeclaredPair
    [DecidableEq Mutant] [DecidableEq World]
    (grid : MutationGrid Mutant World)
    (passed : mutationGridPassed grid = true)
    (mutant : Mutant)
    (world : World)
    (declaredMutant : mutant ∈ grid.mutants)
    (declaredWorld : world ∈ grid.worlds) :
    ∃ index : Nat, ∃ bound : index < grid.observedPairs.length,
      grid.observedPairs[index] = (mutant, world) ∧
      ∀ other : Nat, ∀ otherBound : other < grid.observedPairs.length,
        grid.observedPairs[other] = (mutant, world) → other = index := by
  obtain ⟨index, bound, equality⟩ := List.mem_iff_getElem.mp
    (mutationGridNoMissingDeclaredPair grid passed mutant world declaredMutant declaredWorld)
  refine ⟨index, bound, equality, ?_⟩
  intro other otherBound same
  exact mutationGridNoDuplicateDeclaredPair grid passed other index otherBound bound
    (same.trans equality.symm)

def sampleMutationEvidence (mutant world : Nat) : MutationEvidence Nat Nat :=
  ⟨mutant, world, .passed, .passed, .passed⟩

def sampleMutationGrid : MutationGrid Nat Nat :=
  ⟨[10, 20], [1, 2], [
    sampleMutationEvidence 10 1,
    sampleMutationEvidence 10 2,
    sampleMutationEvidence 20 1,
    sampleMutationEvidence 20 2
  ]⟩

theorem completeSamplePasses : mutationGridPassed sampleMutationGrid = true := by
  decide

theorem omittedPairSampleRejected :
    mutationGridPassed { sampleMutationGrid with
      observed := [sampleMutationEvidence 10 1,
        sampleMutationEvidence 10 2,
        sampleMutationEvidence 20 1] } = false := by
  decide

theorem duplicatePairSampleRejected :
    mutationGridPassed { sampleMutationGrid with
      observed := sampleMutationEvidence 10 1 ::
        { sampleMutationEvidence 10 1 with reached := .failed } ::
        sampleMutationGrid.observed } = false := by
  decide

theorem unknownPairSampleRejected :
    mutationGridPassed { sampleMutationGrid with
      observed := sampleMutationEvidence 30 1 :: sampleMutationGrid.observed } = false := by
  decide

theorem duplicateMutantSampleRejected :
    mutationGridPassed { sampleMutationGrid with mutants := [10, 10, 20] } = false := by
  decide

theorem duplicateWorldSampleRejected :
    mutationGridPassed { sampleMutationGrid with worlds := [1, 1, 2] } = false := by
  decide

end Swiftest
