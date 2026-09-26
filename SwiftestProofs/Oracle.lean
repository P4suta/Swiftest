import SwiftestProofs.Verdict
import SwiftestProofs.Faults

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

def main : IO Unit :=
  IO.print (String.intercalate "\n" (oracleLines ++ faultOracleLines) ++ "\n")
