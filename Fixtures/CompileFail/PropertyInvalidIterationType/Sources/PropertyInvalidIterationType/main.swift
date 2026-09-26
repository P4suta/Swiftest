import SwiftestTesting
import Testing

@Test
@Property(iterations: 1, seed: 1, range: 0...1, predicate: { _ in true })
func propertyWithWrongIterationType() throws {}
