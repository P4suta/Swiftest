import Swiftest

let pipeline = Pipeline<Discovered>.discover(
    DiscoveryCatalog(preservationClaims: .from([]), detectionClaims: .from([]), tests: [])
)
let invalid = pipeline.executed()
print(invalid)
