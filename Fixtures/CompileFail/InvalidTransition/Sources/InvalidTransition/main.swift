import Swiftest

let pipeline = Pipeline<Discovered>.discover(
    DiscoveryCatalog(preservationClaims: [], detectionClaims: [], tests: [])
)
let invalid = pipeline.executed()
print(invalid)
