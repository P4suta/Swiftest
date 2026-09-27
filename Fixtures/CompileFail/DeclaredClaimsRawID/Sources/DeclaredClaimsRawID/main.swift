import Swiftest

let identifier = try ClaimID.parse("preservation-1")
let declared = DeclaredClaims<Preservation>(definitions: [identifier])
print(declared.count)
