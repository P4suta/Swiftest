import SwiftestTesting

@Property(iterations: try .positive(1), seed: 1, range: 0...1, predicate: { _ in true })
func propertyWithoutTest() throws {}
