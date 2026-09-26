import Swiftest

func acceptPreservation(_ claim: Claim<Preservation>) {
    print(claim.name)
}

let detection = try Claim<Detection>.detection(
    id: ClaimID.parse("claim-1"),
    name: "detect"
)
acceptPreservation(detection)
