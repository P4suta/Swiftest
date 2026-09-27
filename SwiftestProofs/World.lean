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

inductive CartesianDigits : List Nat → Type where
  | nil : CartesianDigits []
  | cons {radix : Nat} {radices : List Nat} :
      Fin radix → CartesianDigits radices → CartesianDigits (radix :: radices)

def CartesianDigits.ordinal : {radices : List Nat} → CartesianDigits radices → Nat
  | [], .nil => 0
  | _ :: rest, .cons digit suffix => digit.val * rest.prod + suffix.ordinal

def CartesianDigits.values : {radices : List Nat} → CartesianDigits radices → List Nat
  | [], .nil => []
  | _ :: _, .cons digit suffix => digit.val :: suffix.values

def CartesianDigits.ofOrdinal
    (radices : List Nat)
    (positive : ∀ radix ∈ radices, 0 < radix)
    (ordinal : Nat) : CartesianDigits radices :=
  match radices with
  | [] => .nil
  | radix :: rest =>
      let suffixPositive : ∀ value ∈ rest, 0 < value := by
        intro value membership
        exact positive value (List.mem_cons_of_mem radix membership)
      .cons
        ⟨(ordinal / rest.prod) % radix,
          Nat.mod_lt _ (positive radix (List.mem_cons_self))⟩
        (ofOrdinal rest suffixPositive ordinal)

theorem cartesianOrdinalModulo
    (radices : List Nat)
    (positive : ∀ radix ∈ radices, 0 < radix)
    (ordinal : Nat) :
    (CartesianDigits.ofOrdinal radices positive ordinal).ordinal =
      ordinal % radices.prod := by
  induction radices with
  | nil =>
      simp [CartesianDigits.ofOrdinal, CartesianDigits.ordinal, List.prod_nil, Nat.mod_one]
  | cons radix rest inductionHypothesis =>
      have suffixPositive : ∀ value ∈ rest, 0 < value := by
        intro value membership
        exact positive value (List.mem_cons_of_mem radix membership)
      simp only [CartesianDigits.ofOrdinal, CartesianDigits.ordinal, List.prod_cons]
      rw [inductionHypothesis suffixPositive]
      simpa [Nat.mul_comm, Nat.add_comm] using
        (Nat.mod_mul (x := ordinal) (a := rest.prod) (b := radix)).symm

theorem cartesianOrdinalRoundTrip
    (radices : List Nat)
    (positive : ∀ radix ∈ radices, 0 < radix)
    (ordinal : Nat)
    (bounded : ordinal < radices.prod) :
    (CartesianDigits.ofOrdinal radices positive ordinal).ordinal = ordinal := by
  rw [cartesianOrdinalModulo]
  exact Nat.mod_eq_of_lt bounded

namespace WorldDefinitionEncoding

def length (value : Nat) : List UInt8 :=
  ([56, 48, 40, 32, 24, 16, 8, 0] : List Nat).map fun shift =>
    UInt8.ofNat ((value / 2 ^ shift) % 256)

def string (value : String) : List UInt8 :=
  length value.toUTF8.size ++ value.toUTF8.toList

def rawAxis (name : String) (values : List String) : List UInt8 :=
  string name ++ [0] ++ length values.length ++ values.flatMap string

def compositeAxis (name : String) (values : List (List String)) : List UInt8 :=
  string name ++ [0] ++ length values.length ++
    values.flatMap fun components => components.flatMap string

end WorldDefinitionEncoding

end Swiftest
