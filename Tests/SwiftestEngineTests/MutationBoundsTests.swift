import SwiftestModel
import SwiftestMutation
import Testing

@Test
func mutationApplyRejectsInvalidOffsetsAndLengthsWithoutTrapping() throws {
    let id = try MutantID.parse("mutant-bounds")
    let invalid: [(Int, Int, MutationError)] = [
        (-1, 1, .invalidOffset(-1)),
        (2, 0, .invalidOffset(2)),
        (0, -1, .invalidLength(-1)),
        (0, 2, .invalidRange(0, 2)),
        (1, Int.max, .invalidRange(1, Int.max)),
    ]
    for (offset, length, expected) in invalid {
        let candidate = MutationCandidate(
            id: id,
            schema: .booleanFlip,
            offset: offset,
            length: length,
            replacement: "x"
        )
        do {
            let source = try MutationEngine.apply(candidate, to: "a")
            Issue.record("invalid mutation range was accepted")
            #expect(source.isEmpty)
        } catch let error {
            #expect(error == expected)
        }
    }
    let insertion = MutationCandidate(
        id: id,
        schema: .booleanFlip,
        offset: 1,
        length: 0,
        replacement: "x"
    )
    #expect(try MutationEngine.apply(insertion, to: "a") == "ax")
}
