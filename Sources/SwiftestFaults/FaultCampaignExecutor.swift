import SwiftestModel

public enum FaultScenarioRunResult: Sendable {
    case cleanPassed
    case cleanFailed(Diagnostic)
    case handled([FaultActivationObservation])
    case apparatusFailed(Diagnostic)
}

public struct FaultExecutionTranscript: Sendable {
    let points: [FaultPoint]
    let compounds: [CompoundFault]
    let observations: [FaultScenarioObservation]

    fileprivate init(
        points: [FaultPoint],
        compounds: [CompoundFault],
        observations: [FaultScenarioObservation]
    ) {
        self.points = points
        self.compounds = compounds
        self.observations = observations
    }
}

public enum FaultCampaignExecutor {
    public static func execute(
        campaign: FaultCampaign,
        run: (FaultScenario, inout FaultInjector) -> FaultScenarioRunResult
    ) -> FaultExecutionTranscript {
        let observations = campaign.scenarios.map { scenario in
            var injector = FaultInjector(scenario: scenario)
            let result = run(scenario, &injector)
            switch result {
            case .cleanPassed:
                if scenario.kind == .clean {
                    if campaign.points.contains(where: { !injector.visited($0.id) }) {
                        return failedApparatus(scenario, detail: "clean control did not visit every boundary")
                    }
                    return FaultScenarioObservation(scenario: scenario.id, result: .cleanPassed)
                }
                return failedApparatus(scenario, detail: "injected scenario reported clean")
            case .cleanFailed(let diagnostic):
                return FaultScenarioObservation(scenario: scenario.id, result: .cleanFailed(diagnostic))
            case .apparatusFailed(let diagnostic):
                return FaultScenarioObservation(scenario: scenario.id, result: .apparatusFailed(diagnostic))
            case .handled(let observations):
                if scenario.kind == .clean {
                    return failedApparatus(scenario, detail: "clean scenario reported injection")
                }
                var byPoint: [FaultPointID: FaultActivationObservation] = [:]
                for observation in observations {
                    if !scenario.activations.contains(where: { $0.id == observation.point }) {
                        return failedApparatus(scenario, detail: "undeclared fault observation")
                    }
                    if byPoint.updateValue(observation, forKey: observation.point) != nil {
                        return failedApparatus(scenario, detail: "duplicate fault observation")
                    }
                }
                let unreached = Set(injector.unreachedPoints())
                for observation in observations where unreached.contains(observation.point) {
                    return failedApparatus(scenario, detail: "fault outcome reported without boundary activation")
                }
                let complete = scenario.activations.map { point in
                    if unreached.contains(point.id) {
                        return FaultActivationObservation(point: point.id, result: .unreached)
                    }
                    if let observation = byPoint[point.id] {
                        return observation
                    }
                    return FaultActivationObservation(point: point.id, result: .uncontrolled)
                }
                return FaultScenarioObservation(scenario: scenario.id, result: .injected(complete))
            }
        }
        return FaultExecutionTranscript(
            points: campaign.points,
            compounds: campaign.compounds,
            observations: observations
        )
    }

    private static func failedApparatus(
        _ scenario: FaultScenario,
        detail: String
    ) -> FaultScenarioObservation {
        FaultScenarioObservation(
            scenario: scenario.id,
            result: .apparatusFailed(Diagnostic(
                code: .apparatusFailed,
                subject: scenario.id.rawValue,
                detail: detail
            ))
        )
    }
}
