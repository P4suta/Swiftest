import Swiftest

func acceptRun(_ run: RunID) {
    print(run.rawValue)
}

let claim = try ClaimID.parse("claim-1")
acceptRun(claim)
