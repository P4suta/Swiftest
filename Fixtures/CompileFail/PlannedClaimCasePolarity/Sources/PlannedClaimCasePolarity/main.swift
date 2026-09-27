import Swiftest

func acceptPreservation(_ value: PlannedClaimCaseID<Preservation>) {}

func rejectDetection(_ value: PlannedClaimCaseID<Detection>) {
    acceptPreservation(value)
}
