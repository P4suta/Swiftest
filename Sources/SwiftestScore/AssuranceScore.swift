import SwiftestModel

public struct AssuranceScore: Equatable, Sendable {
    public let passed: EvidenceCount
    public let total: EvidenceCount

    private init(passed: EvidenceCount, total: EvidenceCount) {
        self.passed = passed
        self.total = total
    }

    public static func measure(_ catalog: EvidenceCatalog) throws(NumericValueError) -> AssuranceScore {
        let claimStatuses = catalog.claimObservations.map(\.status)
        let mutationStatuses: [ObservationStatus] = catalog.mutationObservations.map {
            $0.isSuccessful ? .passed : .failed
        }
        let lawStatuses = catalog.lawObservations.map(\.status)
        let schemaStatuses = catalog.schemaObservations.map(\.status)
        let statuses = claimStatuses + mutationStatuses + lawStatuses + schemaStatuses
        let passedValue = statuses.filter { $0 == .passed }.count
        return AssuranceScore(
            passed: try .nonnegative(passedValue),
            total: try .nonnegative(statuses.count)
        )
    }

    public var ratioDescription: String {
        String(passed.rawValue) + "/" + String(total.rawValue)
    }
}
