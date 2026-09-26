public actor CallLedger<Input: Sendable> {
    private var values: [Input] = []

    public init() {}

    public func record(_ value: sending Input) {
        values.append(value)
    }

    public func recordedValues() -> [Input] {
        values
    }
}

public struct Stub<Input: Sendable, Output: Sendable>: Sendable {
    private let implementation: @Sendable (Input) async -> Output

    public init(implementation: @escaping @Sendable (Input) async -> Output) {
        self.implementation = implementation
    }

    public func call(_ input: Input) async -> Output {
        await implementation(input)
    }
}
