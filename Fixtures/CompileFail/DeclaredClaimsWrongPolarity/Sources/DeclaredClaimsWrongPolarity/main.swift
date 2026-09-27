import Swiftest

let detection = try Claim<Detection>.detection(
    id: ClaimID.parse("detection-1"),
    name: "detect"
)
let declared = DeclaredClaims<Preservation>.from([detection])
print(declared.count)
