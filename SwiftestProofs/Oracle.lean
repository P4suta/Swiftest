import SwiftestProofs.Verdict
import SwiftestProofs.Faults
import SwiftestProofs.Path

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
  .unverified
]

def faultEvidenceText : FaultEvidenceState → String
  | .verified => "verified"
  | .structural => "structural"
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

def main : IO Unit :=
  IO.print (String.intercalate "\n"
    (oracleLines ++ faultOracleLines ++ boundaryOracleLines ++ reportOracleLines ++ pathOracleLines) ++ "\n")
