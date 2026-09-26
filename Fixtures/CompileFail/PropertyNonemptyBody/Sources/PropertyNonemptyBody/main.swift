import SwiftestTesting
import Testing

@Test
@Property(iterations: try .positive(1), seed: 1, range: 0...1, predicate: { _ in true })
func propertyWithBody() throws {
    #expect(true)
}
