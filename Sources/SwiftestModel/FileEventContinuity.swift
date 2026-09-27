public enum FileEventContinuity: String, CaseIterable, Equatable, Sendable {
    case eventFree = "event-free"
    case attributeAmbiguous = "attribute-ambiguous"

    public func joined(with other: FileEventContinuity) -> FileEventContinuity {
        switch (self, other) {
        case (.eventFree, .eventFree):
            .eventFree
        case (.eventFree, .attributeAmbiguous),
            (.attributeAmbiguous, .eventFree),
            (.attributeAmbiguous, .attributeAmbiguous):
            .attributeAmbiguous
        }
    }
}
