namespace Swiftest

inductive WireKey where
  | schema
  | run
  | scope
  | verdict
  | score
  | executionCount
  | catalogDigest
  | faults
deriving DecidableEq, Repr

def reportKeys : List WireKey := [
  .schema,
  .run,
  .scope,
  .verdict,
  .score,
  .executionCount,
  .catalogDigest,
  .faults
]

structure StrictObject where
  keys : List WireKey
  noDuplicates : keys.Nodup
  noUnknownFields : ∀ key, key ∈ keys → key ∈ reportKeys

theorem acceptedWireHasNoDuplicateKeys (object : StrictObject) : object.keys.Nodup := by
  exact object.noDuplicates

theorem acceptedWireHasNoUnknownFields
    (object : StrictObject)
    (key : WireKey)
    (present : key ∈ object.keys) :
    key ∈ reportKeys := by
  exact object.noUnknownFields key present

example : reportKeys.Nodup := by
  decide

end Swiftest
