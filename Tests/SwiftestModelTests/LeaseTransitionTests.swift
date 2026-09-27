import SwiftestModel
import Testing

@Test
func leaseTransitionRejectsInvalidInventories() {
    for count in [0, -1, Int.max] {
        do {
            let transition = try LeaseTransition.begin(registrationCount: count)
            Issue.record("invalid lease inventory was accepted: \(transition)")
        } catch let error {
            switch count {
            case 0, -1:
                #expect(error == .emptyInventory)
            case Int.max:
                #expect(error == .inventoryOverflow)
            default:
                Issue.record("unexpected inventory case")
            }
        }
    }
}

@Test
func leaseMutationAndQueueErrorAreAbsorbing() throws {
    for observation in [
        LeaseObservation.mutation,
        .unknownDescriptor,
        .queueUnavailable,
    ] {
        let initial = try LeaseTransition.begin(registrationCount: 1)
        let invalid = initial.observing(observation)
        #expect(invalid == .invalid)
        #expect(invalid.observing(.quiescent) == .invalid)
        #expect(invalid.observing(.attributeAmbiguous) == .invalid)
    }
}

@Test
func leaseAttributeAmbiguityIsStickyAndBudgeted() throws {
    var transition = try LeaseTransition.begin(registrationCount: 1)
    for remaining in [3, 2, 1, 0] {
        transition = transition.observing(.attributeAmbiguous)
        if case .polling(let budget, let continuity) = transition {
            #expect(budget.remainingAttributes == remaining)
            #expect(continuity == .attributeAmbiguous)
        } else {
            Issue.record("attribute observation stopped polling before budget exhaustion")
        }
    }
    #expect(transition.observing(.quiescent) == .verified(.attributeAmbiguous))
    #expect(transition.observing(.attributeAmbiguous) == .invalid)
}

@Test
func leaseEventFreeContinuityRequiresNoAttributeEvent() throws {
    let initial = try LeaseTransition.begin(registrationCount: 1)
    let verified = initial.observing(.quiescent)
    #expect(verified == .verified(.eventFree))
    #expect(verified.observing(.mutation) == verified)
}

@Test
func leaseOracleCoversCriticalTransitions() throws {
    let lines = try LeaseOracle.text().split(separator: "\n")
    #expect(lines.count == 327)
    #expect(lines.contains("lease\tmutation\tinvalid"))
    #expect(lines.contains("lease\tattribute-quiet\tverified-attribute-ambiguous"))
    #expect(lines.contains("lease\tfive-attributes\tinvalid"))
    #expect(lines.contains("lease\tquiet-then-mutation\tverified-event-free"))
}
