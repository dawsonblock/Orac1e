import Foundation
import Testing
@testable import OracleOS

@Suite("Strategy-Scoped Workflow Filtering")
struct StrategyScopedWorkflowTests {

    // MARK: - WorkflowMatcher

    @Test("WorkflowMatcher filters workflows outside strategy scope")
    func matcherFiltersOutsideScope() {
        let matcher = WorkflowMatcher()
        let index = WorkflowIndex()

        let repoStrategy = SelectedStrategy(
            kind: .repoRepair,
            confidence: 0.8,
            rationale: "repo repair strategy",
            allowedOperatorFamilies: [.repoAnalysis, .patchGeneration, .recovery]
        )

        let matches = matcher.match(
            currentState: .repoLoaded,
            workflowIndex: index,
            selectedStrategy: repoStrategy
        )

        // No promoted workflows exist in empty index
        #expect(matches.isEmpty)
    }

    @Test("WorkflowMatcher requires strategy argument (non-optional)")
    func matcherRequiresStrategy() {
        let matcher = WorkflowMatcher()
        let index = WorkflowIndex()

        let browserStrategy = SelectedStrategy(
            kind: .browserInteraction,
            confidence: 0.7,
            rationale: "browser interaction strategy",
            allowedOperatorFamilies: [.browserTargeted, .hostTargeted]
        )

        let matches = matcher.match(
            currentState: .loginPageDetected,
            workflowIndex: index,
            selectedStrategy: browserStrategy
        )

        #expect(matches.isEmpty)
    }

    // MARK: - WorkflowRetriever

    @Test("WorkflowRetriever requires strategy argument (non-optional)")
    func retrieverRequiresStrategy() {
        let retriever = WorkflowRetriever()
        let goal = Goal(description: "fix tests", preferredAgentKind: .code)
        let worldState = makeWorldState(app: "Workspace")

        let repoStrategy = SelectedStrategy(
            kind: .repoRepair,
            confidence: 0.8,
            rationale: "repo repair strategy",
            allowedOperatorFamilies: [.repoAnalysis, .patchGeneration, .recovery]
        )

        let workspaceRoot = URL(fileURLWithPath: "/tmp/ws", isDirectory: true)
        let taskContext = TaskContext.from(goal: goal, workspaceRoot: workspaceRoot)

        let match = retriever.retrieve(
            goal: goal,
            taskContext: taskContext,
            worldState: worldState,
            workflowIndex: WorkflowIndex(),
            selectedStrategy: repoStrategy
        )

        // Empty index → no match, but should not crash
        #expect(match == nil)
    }

    // MARK: - Helpers

    private func makeWorldState(app: String) -> WorldState {
        WorldState(
            observationHash: "hash-\(app)",
            planningState: PlanningState(
                id: PlanningStateID(rawValue: "\(app)|state"),
                clusterKey: StateClusterKey(rawValue: "\(app)|state"),
                appID: app,
                domain: nil,
                windowClass: nil,
                taskPhase: "test",
                focusedRole: nil,
                modalClass: nil,
                navigationClass: nil,
                controlContext: nil
            ),
            observation: Observation(
                app: app,
                windowTitle: app,
                url: nil,
                focusedElementID: nil,
                elements: []
            ),
            repositorySnapshot: nil
        )
    }
}
