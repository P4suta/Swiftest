import Foundation
import Swiftest

let discovery = DiscoveryCatalog(
    preservationClaims: .from([]),
    detectionClaims: .from([]),
    tests: [try TestID.parse("test-1")]
)
let plan = FrozenPlan(
    run: try RunID.parse("run-1"),
    worlds: .unmodeledHosts([try WorldID.parse("world-1")]),
    mutants: [],
    digest: try Digest.sha256(Data("plan".utf8))
)
let discovered = Pipeline<Discovered>.discover(discovery)
let planned = try discovered.plan()
let frozen = planned.freeze(plan)
let invalid = try frozen.built()
