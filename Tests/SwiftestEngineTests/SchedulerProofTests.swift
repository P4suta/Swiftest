import SwiftestModel
import SwiftestScheduler
import Testing

@Test
func reductionPreservesEveryThreeTaskDependencyClass() throws {
    let firstResource = try ResourceID.parse("first")
    let secondResource = try ResourceID.parse("second")
    let accesses = [
        ResourceAccess(resource: firstResource, mode: .read),
        ResourceAccess(resource: firstResource, mode: .write),
        ResourceAccess(resource: secondResource, mode: .read),
        ResourceAccess(resource: secondResource, mode: .write),
    ]
    for first in accesses {
        for second in accesses {
            for third in accesses {
                let tasks = [
                    [try ScheduledAction(id: "first", task: 0, accesses: [first])],
                    [try ScheduledAction(id: "second", task: 1, accesses: [second])],
                    [try ScheduledAction(id: "third", task: 2, accesses: [third])],
                ]
                let full = try DeterministicScheduler.traces(tasks: tasks, proofMode: .disabled)
                let reduced = try DeterministicScheduler.traces(tasks: tasks, proofMode: .enabled)
                try DPORProofKernel.verify(full: full, reduced: reduced)
                let fullSequences = Set(full.map { $0.actions.map(\.id) })
                let reducedSequences = Set(reduced.map { $0.actions.map(\.id) })
                #expect(reducedSequences.isSubset(of: fullSequences))
                #expect(reduced.count <= full.count)
            }
        }
    }
}
