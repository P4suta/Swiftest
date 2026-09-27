import Foundation
import Swiftest

let digest = try Digest.sha256(Data("plan".utf8))
let plan = FrozenPlan(
    run: try RunID.parse("run-1"),
    worlds: .unmodeledHosts([try WorldID.parse("world-1")]),
    mutants: [],
    digest: digest
)
let forged = BuildReceipt(plan: plan, artifactDigest: digest)
