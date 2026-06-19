import Foundation
import Testing
@testable import OracleOS

/// Verifies the world-model diff/reset primitives directly.
/// These tests cover `WorldStateModel` and `StateDiffEngine`, not AgentLoop.
@Suite("WorldModel State Wiring")
struct WorldModelAgentLoopWiringTests {

    // MARK: - WorldStateModel incremental update contract

    @Test("WorldStateModel accepts StateDiff from StateDiffEngine")
    func worldModelAppliesDiff() {
        let model = WorldStateModel()
        // Build a minimal WorldState to diff against the empty model
        let obs = Observation(
            app: "TestApp",
            windowTitle: "Window A",
            url: nil,
            elements: [],
            focusedElementID: nil
        )
        let planningState = PlanningState(
            id: PlanningStateID(rawValue: "state-1"),
            app: "TestApp",
            windowTitle: "Window A",
            url: nil,
            focusedRole: nil,
            focusedLabel: nil,
            keyboardFocused: false,
            modalClass: nil,
            scrollable: false,
            elementDensity: .empty,
            domain: "os",
            agentKind: .os
        )
        let worldState = WorldState(
            observationHash: "hash-1",
            planningState: planningState,
            observation: obs,
            repositorySnapshot: nil
        )
        let diff = StateDiffEngine.diff(current: model.snapshot, incoming: worldState)
        model.apply(diff: diff)

        #expect(model.snapshot.activeApplication == "TestApp")
        #expect(model.snapshot.windowTitle == "Window A")
        #expect(model.recentHistory(limit: 5).count == 1)
    }

    @Test("WorldStateModel history grows after sequential commits")
    func historyGrowsAfterCommits() {
        let model = WorldStateModel()
        for i in 1...3 {
            let obs = Observation(
                app: "App\(i)",
                windowTitle: "W\(i)",
                url: nil,
                elements: [],
                focusedElementID: nil
            )
            let planningState = PlanningState(
                id: PlanningStateID(rawValue: "state-\(i)"),
                app: "App\(i)",
                windowTitle: "W\(i)",
                url: nil,
                focusedRole: nil,
                focusedLabel: nil,
                keyboardFocused: false,
                modalClass: nil,
                scrollable: false,
                elementDensity: .empty,
                domain: "os",
                agentKind: .os
            )
            let ws = WorldState(
                observationHash: "hash-\(i)",
                planningState: planningState,
                observation: obs,
                repositorySnapshot: nil
            )
            let diff = StateDiffEngine.diff(current: model.snapshot, incoming: ws)
            model.apply(diff: diff)
        }
        #expect(model.snapshot.activeApplication == "App3")
        #expect(model.recentHistory(limit: 10).count == 3)
    }

    @Test("StateDiffEngine produces empty diff when state is unchanged")
    func emptyDiffWhenUnchanged() {
        let model = WorldStateModel()
        let obs = Observation(app: "A", windowTitle: "T", url: nil, focusedElementID: nil, elements: [])
        let ps = PlanningState(
            id: PlanningStateID(rawValue: "s"),
            app: "A",
            windowTitle: "T",
            url: nil,
            focusedRole: nil,
            focusedLabel: nil,
            keyboardFocused: false,
            modalClass: nil,
            scrollable: false,
            elementDensity: .empty,
            domain: "os",
            agentKind: .os
        )
        let ws = WorldState(observationHash: "h", planningState: ps, observation: obs, repositorySnapshot: nil)
        model.reset(from: ws)

        // Diff the already-committed state against itself — should be empty
        let diff = StateDiffEngine.diff(current: model.snapshot, incoming: ws)
        #expect(diff.isEmpty)
    }
}
