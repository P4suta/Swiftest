import SwiftestProofs.Verdict
import SwiftestProofs.Faults
import SwiftestProofs.Lease
import SwiftestProofs.Path
import SwiftestProofs.SAT
import SwiftestProofs.World

open Swiftest

def signals : List Signal := [.absent, .present]

def scopes : List Scope := [.complete, .change, .scoped]

def signalText : Signal → String
  | .absent => "absent"
  | .present => "present"

def scopeText : Scope → String
  | .complete => "complete"
  | .change => "change"
  | .scoped => "scoped"

def verdictText : Verdict → String
  | .assured => "ASSURED"
  | .changeAssured => "CHANGE_ASSURED"
  | .scopeAssured => "SCOPE_ASSURED"
  | .unsettled => "UNSETTLED"
  | .gaps => "GAPS"
  | .gapsAndUnsettled => "GAPS+UNSETTLED"
  | .invalid => "INVALID"

def oracleLines : List String :=
  signals.flatMap fun apparatus =>
    signals.flatMap fun gap =>
      signals.flatMap fun unsettled =>
        scopes.map fun scope =>
          String.intercalate "\t" [
            signalText apparatus,
            signalText gap,
            signalText unsettled,
            scopeText scope,
            verdictText (verdict apparatus gap unsettled scope)
          ]

def faultAcceptanceText (result : FaultResult) : String :=
  if acceptedFaultResult result then "accepted" else "rejected"

def faultOracleLines : List String :=
  faultResults.map fun result =>
    String.intercalate "\t" [
      "fault",
      faultResultText result,
      faultAcceptanceText result
    ]

def boundaryReports : List (Option FaultResult) :=
  none :: faultResults.map some

def boundaryReachText : Bool → String
  | false => "unreached"
  | true => "reached"

def boundaryReportText : Option FaultResult → String
  | none => "missing"
  | some result => faultResultText result

def boundaryOracleLines : List String :=
  [false, true].flatMap fun reached =>
    boundaryReports.map fun reported =>
      String.intercalate "\t" [
        "fault-boundary",
        boundaryReachText reached,
        boundaryReportText reported,
        if acceptedExecutedResult (recordBoundaryResult reached reported)
          then "accepted" else "rejected"
      ]

def allVerdicts : List Verdict := [
  .assured,
  .changeAssured,
  .scopeAssured,
  .unsettled,
  .gaps,
  .gapsAndUnsettled,
  .invalid
]

def faultEvidenceStates : List FaultEvidenceState := [
  .verified,
  .structural,
  .scoped,
  .unverified
]

def faultEvidenceText : FaultEvidenceState → String
  | .verified => "verified"
  | .structural => "structural"
  | .scoped => "partial"
  | .unverified => "unverified"

def reportOracleLines : List String :=
  allVerdicts.flatMap fun base =>
    faultEvidenceStates.map fun faults =>
      String.intercalate "\t" [
        "report",
        verdictText base,
        faultEvidenceText faults,
        verdictText (reportVerdict base faults)
      ]

def pathOracleLines : List String :=
  pathOracleCases.map fun entry =>
    String.intercalate "\t" [
      "path",
      entry.1,
      pathDecisionText (classifyPath entry.2)
    ]

def satLiterals : List (String × Literal) := [
  ("x", ⟨1, true⟩),
  ("not-x", ⟨1, false⟩),
  ("y", ⟨2, true⟩),
  ("not-y", ⟨2, false⟩)
]

def satAssignment (x y : Bool) : Assignment :=
  fun index => if index == 1 then x else if index == 2 then y else false

def satOutcome (formula : Formula) : String :=
  if [false, true].any (fun x =>
    [false, true].any (fun y => verifySAT formula (satAssignment x y))) then
    "satisfiable"
  else
    "unsatisfiable"

def satOracleLines : List String :=
  satLiterals.flatMap fun left =>
    satLiterals.map fun right =>
      String.intercalate "\t" [
        "sat",
        left.1,
        right.1,
        satOutcome [[left.2], [right.2]]
      ]

def leaseOracleLines : List String :=
  leaseOracleCases.map fun entry =>
    String.intercalate "\t" [
      "lease",
      entry.1,
      leaseTransitionText
        (runLeaseTrace (.polling (entry.2.1 * 4) .eventFree) entry.2.2)
    ]

def leaseWitnessOracleLines : List String :=
  ([0, 1, 2, 4] : List Nat).map fun count =>
    match repeatedAttributeWitness count with
    | some witness =>
        String.intercalate "\t" [
          "lease-witness",
          toString count,
          leaseContinuityText witness.continuity,
          toString witness.generation
        ]
    | none => String.intercalate "\t" ["lease-witness", toString count, "overflow"]

def leaseGenerationOracleLines : List String :=
  ([0, maxFileEventGeneration - 1, maxFileEventGeneration] : List Nat).map fun current =>
    let result := match advanceFileEventGeneration current with
      | some next => toString next
      | none => "overflow"
    String.intercalate "\t" ["lease-generation", toString current, result]

def leaseOriginOracleLines : List String :=
  let first := healthRecordingAttribute initialLeaseHealth 1
  let second := first.bind (fun state => healthRecordingAttribute state 2)
  ([(0, some initialLeaseHealth), (1, first), (2, second)] :
    List (Nat × Option LeaseHealth)).map fun entry =>
    match entry.2 with
    | none => String.intercalate "\t" ["lease-origin", toString entry.1, "overflow"]
    | some health =>
        let origin := match health.firstPath with
          | none => "absent"
          | some path => toString path
        String.intercalate "\t" [
          "lease-origin",
          toString entry.1,
          origin,
          toString health.witness.generation,
          leaseContinuityText health.witness.continuity
        ]

def worldCursorRadices : List Nat := [2, 3, 2, 2, 2]

theorem worldCursorRadicesPositive : ∀ radix ∈ worldCursorRadices, 0 < radix := by
  decide

theorem worldCursorRadicesCount : worldCursorRadices.prod = 48 := by
  decide

def worldCursorOracleLines : List String :=
  [String.intercalate "\t" ["world-cursor-count", toString worldCursorRadices.prod]] ++
    (List.range worldCursorRadices.prod).map fun ordinal =>
      let digits := CartesianDigits.ofOrdinal worldCursorRadices
        worldCursorRadicesPositive ordinal
      String.intercalate "\t" <|
        ["world-cursor", toString ordinal] ++
        digits.values.map toString ++ [toString (ordinal / 2)]

def worldDefinitionPreimage (locales : List String) : List UInt8 :=
  WorldDefinitionEncoding.string "swiftest.world-definition.v1" ++
  WorldDefinitionEncoding.rawAxis "build" ["debug", "release"] ++
  WorldDefinitionEncoding.rawAxis "operating-system" ["iOS"] ++
  WorldDefinitionEncoding.compositeAxis "device" [["oracle-device", "phone"]] ++
  WorldDefinitionEncoding.rawAxis "locale" locales ++
  WorldDefinitionEncoding.rawAxis "layout-direction" ["left-to-right"] ++
  WorldDefinitionEncoding.rawAxis "appearance" ["light", "dark"] ++
  WorldDefinitionEncoding.rawAxis "accessibility" ["standard"] ++
  WorldDefinitionEncoding.compositeAxis "permission"
    [["camera", "granted"], ["camera", "denied"]] ++
  WorldDefinitionEncoding.rawAxis "location" ["fixed"] ++
  WorldDefinitionEncoding.rawAxis "biometrics" ["succeeds"] ++
  WorldDefinitionEncoding.rawAxis "lifecycle" ["foreground"] ++
  WorldDefinitionEncoding.rawAxis "data" ["typical"] ++
  WorldDefinitionEncoding.rawAxis "service-fault" ["none"] ++
  WorldDefinitionEncoding.rawAxis "cancellation" ["never"] ++
  WorldDefinitionEncoding.string "schedule" ++ [0] ++
    WorldDefinitionEncoding.length 1 ++
    WorldDefinitionEncoding.string "oracle-schedule" ++
    WorldDefinitionEncoding.length 0

def baselineWorldDefinitionPreimage : List UInt8 :=
  worldDefinitionPreimage ["en-US", "ja-JP", "ar-SA"]

def changedLocaleWorldDefinitionPreimage : List UInt8 :=
  worldDefinitionPreimage ["de-DE", "ja-JP", "ar-SA"]

theorem changedLocaleWorldDefinitionPreimageDiffers :
    baselineWorldDefinitionPreimage ≠ changedLocaleWorldDefinitionPreimage := by
  decide +kernel

def worldDefinitionPreimageText (bytes : List UInt8) : String :=
  String.intercalate "," (bytes.map fun byte => toString byte.toNat)

def worldDefinitionOracleLines : List String :=
  [
    String.intercalate "\t" ["world-definition-preimage", "baseline",
      worldDefinitionPreimageText baselineWorldDefinitionPreimage],
    String.intercalate "\t" ["world-definition-preimage", "locale-value",
      worldDefinitionPreimageText changedLocaleWorldDefinitionPreimage],
    String.intercalate "\t" ["world-definition-preimage", "mutant-order",
      worldDefinitionPreimageText baselineWorldDefinitionPreimage]
  ]

def main : IO Unit :=
  IO.print (String.intercalate "\n"
    (oracleLines ++ faultOracleLines ++ boundaryOracleLines ++ reportOracleLines ++ pathOracleLines
      ++ satOracleLines ++ leaseOracleLines ++ leaseWitnessOracleLines
      ++ leaseGenerationOracleLines ++ leaseOriginOracleLines
      ++ worldCursorOracleLines ++ worldDefinitionOracleLines) ++ "\n")
