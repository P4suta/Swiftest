import Foundation
import Swiftest

let plan = FrozenPlan(
    run: try RunID.parse("run-1"),
    worlds: [try WorldID.parse("world-1")],
    mutants: [],
    digest: try Digest.sha256(Data("plan".utf8))
)
print(plan.worlds.count)
