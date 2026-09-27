public struct DeclaredClaims<Polarity>: Collection, Equatable, Sendable {
    public typealias Element = ClaimID
    public typealias Index = Int

    public let definitions: [Claim<Polarity>]

    private init(definitions: [Claim<Polarity>]) {
        self.definitions = definitions
    }

    public static func from(_ claims: [Claim<Polarity>]) -> Self {
        Self(definitions: claims)
    }

    public var startIndex: Int {
        definitions.startIndex
    }

    public var endIndex: Int {
        definitions.endIndex
    }

    public func index(after index: Int) -> Int {
        definitions.index(after: index)
    }

    public subscript(position: Int) -> ClaimID {
        definitions[position].id
    }
}
