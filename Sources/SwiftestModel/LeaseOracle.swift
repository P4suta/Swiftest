public enum LeaseOracle {
    private struct Case {
        let label: String
        let registrationCount: Int
        let observations: [LeaseObservation]
    }

    public static func text() throws(LeaseTransitionError) -> String {
        let attribute = LeaseObservation.attributeAmbiguous
        let boundarySamples: [Case] = [
            Case(label: "empty-trace", registrationCount: 1, observations: []),
            Case(label: "quiet", registrationCount: 1, observations: [.quiescent]),
            Case(label: "mutation", registrationCount: 1, observations: [.mutation, .quiescent]),
            Case(label: "unknown", registrationCount: 1, observations: [.unknownDescriptor, .quiescent]),
            Case(label: "queue-error", registrationCount: 1, observations: [.queueUnavailable, .quiescent]),
            Case(label: "attribute", registrationCount: 1, observations: [attribute]),
            Case(label: "attribute-quiet", registrationCount: 1, observations: [attribute, .quiescent]),
            Case(label: "attribute-mutation", registrationCount: 1, observations: [attribute, .mutation, .quiescent]),
            Case(label: "attribute-unknown", registrationCount: 1, observations: [attribute, .unknownDescriptor, .quiescent]),
            Case(label: "attribute-queue-error", registrationCount: 1,
                observations: [attribute, .queueUnavailable, .quiescent]),
            Case(label: "four-attributes", registrationCount: 1,
                observations: Array(repeating: attribute, count: 4) + [.quiescent]),
            Case(label: "five-attributes", registrationCount: 1,
                observations: Array(repeating: attribute, count: 5) + [.quiescent]),
            Case(label: "larger-inventory", registrationCount: 2,
                observations: Array(repeating: attribute, count: 5) + [.quiescent]),
            Case(label: "quiet-then-mutation", registrationCount: 1,
                observations: [.quiescent, .mutation]),
            Case(label: "attribute-then-quiet-then-mutation", registrationCount: 1,
                observations: [attribute, .quiescent, .mutation]),
        ]
        let samples = boundarySamples + gridCases()
        let lines = try samples.map { sample throws(LeaseTransitionError) -> String in
            var state = try LeaseTransition.begin(registrationCount: sample.registrationCount)
            for observation in sample.observations {
                state = state.observing(observation)
            }
            let outcome: String
            switch state {
            case .polling(_, .eventFree):
                outcome = "polling-event-free"
            case .polling(_, .attributeAmbiguous):
                outcome = "polling-attribute-ambiguous"
            case .verified(.eventFree):
                outcome = "verified-event-free"
            case .verified(.attributeAmbiguous):
                outcome = "verified-attribute-ambiguous"
            case .invalid:
                outcome = "invalid"
            }
            return ["lease", sample.label, outcome].joined(separator: "\t")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func gridCases() -> [Case] {
        let observations: [(String, LeaseObservation)] = [
            ("quiet", .quiescent),
            ("attribute", .attributeAmbiguous),
            ("mutation", .mutation),
            ("unknown", .unknownDescriptor),
            ("queue-error", .queueUnavailable),
        ]
        var traces: [(String, [LeaseObservation])] = [("none", [])]
        for _ in 0..<3 {
            var expanded: [(String, [LeaseObservation])] = [("none", [])]
            for (label, observation) in observations {
                for (suffix, events) in traces {
                    let name = suffix == "none" ? label : label + "-" + suffix
                    expanded.append((name, [observation] + events))
                }
            }
            traces = expanded
        }
        return [1, 2].flatMap { count in
            traces.map { label, events in
                Case(label: "grid-\(count)-\(label)", registrationCount: count, observations: events)
            }
        }
    }
}
