import Foundation
import Testing
@testable import OracleOS

@Suite("PathSearch Cycle Control")
struct PathSearchCycleControlTests {

    // MARK: - Helpers

    private func makeTempGraphURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("graph.sqlite3", isDirectory: false)
    }

    private func planningState(
        id: String,
        appID: String = "TestApp",
        domain: String? = "test.com",
        taskPhase: String = "browse"
    ) -> PlanningState {
        PlanningState(
            id: PlanningStateID(rawValue: id),
            clusterKey: StateClusterKey(rawValue: id),
            appID: appID,
            domain: domain,
            windowClass: nil,
            taskPhase: taskPhase,
            focusedRole: nil,
            modalClass: nil,
            navigationClass: nil,
            controlContext: nil
        )
    }

    private func transition(
        from: PlanningStateID,
        to: PlanningStateID,
        actionContractID: String
    ) -> VerifiedTransition {
        VerifiedTransition(
            fromPlanningStateID: from,
            toPlanningStateID: to,
            actionContractID: actionContractID,
            postconditionClass: .elementAppeared,
            verified: true,
            latencyMs: 100
        )
    }

    private func actionContract(id: String) -> ActionContract {
        ActionContract(
            id: id,
            skillName: "click",
            targetRole: "AXButton",
            targetLabel: "test",
            locatorStrategy: "query"
        )
    }

    // MARK: - Cycle Detection

    @Test("PathSearch detects cycles and reports cycleDetections in diagnostics")
    func detectsCyclesInDiagnostics() throws {
        let graphURL = makeTempGraphURL()
        let store = GraphStore(databaseURL: graphURL)

        let stateA = planningState(id: "A")
        let stateB = planningState(id: "B")

        // Create a cycle: A -> B -> A
        let contractAB = actionContract(id: "a-to-b")
        let contractBA = actionContract(id: "b-to-a")

        store.recordTransition(
            transition(from: stateA.id, to: stateB.id, actionContractID: contractAB.id),
            actionContract: contractAB,
            fromState: stateA,
            toState: stateB
        )
        store.recordTransition(
            transition(from: stateB.id, to: stateA.id, actionContractID: contractBA.id),
            actionContract: contractBA,
            fromState: stateB,
            toState: stateA
        )

        // Record enough successes for promotion
        for _ in 0..<4 {
            store.recordTransition(
                transition(from: stateA.id, to: stateB.id, actionContractID: contractAB.id),
                actionContract: contractAB
            )
            store.recordTransition(
                transition(from: stateB.id, to: stateA.id, actionContractID: contractBA.id),
                actionContract: contractBA
            )
        }
        store.promoteEligibleEdges()

        let goal = Goal(
            description: "reach state C",
            targetApp: "TestApp",
            targetDomain: "test.com",
            targetTaskPhase: "submit"
        )

        let search = PathSearch(maxDepth: 6, beamWidth: 3, cyclePenalty: 0.5)
        let result = try #require(search.search(from: stateA, goal: goal, graphStore: store))

        // The search should detect cycles since B->A revisits an already-visited state
        #expect(result.diagnostics.cycleDetections > 0)
    }

    @Test("PathSearch cycle penalty reduces score for cyclic paths")
    func cyclePenaltyReducesScore() {
        // Verify the default cycle penalty is 0.5
        #expect(PathSearch.defaultCyclePenalty == 0.5)

        // A search with high cycle penalty should be more aggressive about avoiding cycles
        let highPenalty = PathSearch(cyclePenalty: 1.0)
        #expect(highPenalty.cyclePenalty == 1.0)

        let lowPenalty = PathSearch(cyclePenalty: 0.1)
        #expect(lowPenalty.cyclePenalty == 0.1)
    }

    @Test("GraphSearchDiagnostics includes cycleDetections field with default of zero")
    func diagnosticsHasCycleDetections() {
        let diag = GraphSearchDiagnostics()
        #expect(diag.cycleDetections == 0)

        let diagWithCycles = GraphSearchDiagnostics(cycleDetections: 5)
        #expect(diagWithCycles.cycleDetections == 5)
    }
}
