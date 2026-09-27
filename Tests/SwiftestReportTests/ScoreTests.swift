import SwiftestModel
import SwiftestScore
import Testing

@Test
func mutationScoreRequiresReachInfectionAndDetection() throws {
    let mutant = try MutantID.parse("mutant-score")
    let world = try WorldID.parse("world-score")
    let cases: [(
        reached: ObservationStatus,
        infected: ObservationStatus,
        detected: ObservationStatus,
        passed: Int
    )] = [
        (.failed, .passed, .passed, 0),
        (.passed, .failed, .passed, 0),
        (.passed, .passed, .failed, 0),
        (.passed, .passed, .passed, 1),
    ]
    for item in cases {
        let catalog = EvidenceCatalog(
            run: try RunID.parse("run-score"),
            scope: .complete,
            inputContinuity: .eventFree,
            runtimePipeline: .unverified,
            preservationClaims: .from([]),
            detectionClaims: .from([]),
            worlds: .unmodeledHosts([world]),
            mutants: [mutant],
            claimObservations: [],
            mutationObservations: [MutationObservation(
                mutant: mutant,
                world: world,
                reached: item.reached,
                infected: item.infected,
                detected: item.detected
            )],
            lawObservations: [],
            schemaObservations: [],
            failures: [],
            review: IndependentReview(status: .pending, evidence: nil),
            executionCount: try EvidenceCount.nonnegative(1)
        )
        let score = try AssuranceScore.measure(catalog)
        #expect(score.total.rawValue == 1)
        #expect(score.passed.rawValue == item.passed)
        #expect(catalog.coverageGaps.contains(where: {
            $0.subject == "mutant-score:world-score"
        }) == (item.passed == 0))
    }
}
