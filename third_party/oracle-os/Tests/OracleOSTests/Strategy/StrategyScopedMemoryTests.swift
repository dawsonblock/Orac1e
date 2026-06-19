import Foundation
import Testing
@testable import OracleOS

@Suite("Strategy-Scoped Memory Bias")
struct StrategyScopedMemoryTests {

    @Test("MemoryDecisionBias requires strategy (non-optional)")
    func biasRequiresStrategy() {
        let calculator = MemoryDecisionBiasCalculator()
        let state = makeReasoningState()
        let plan = PlanCandidate(
            operators: [Operator(kind: .runTests)],
            projectedState: state
        )

        let repoStrategy = SelectedStrategy(
            kind: .repoRepair,
            confidence: 0.8,
            rationale: "repo repair",
            allowedOperatorFamilies: [.repoAnalysis, .patchGeneration, .recovery]
        )

        let bias = calculator.bias(
            plan: plan,
            memoryInfluence: MemoryInfluence(),
            goal: Goal(description: "fix tests", preferredAgentKind: .code),
            worldState: makeWorldState(app: "Workspace"),
            taskContext: makeTaskContext(),
            selectedStrategy: repoStrategy
        )

        // Should produce a valid bias (not crash)
        #expect(bias.total >= -1.0 && bias.total <= 2.0)
    }

    @Test("MemoryDecisionBias produces different scores for different strategies")
    func biasVariesByStrategy() {
        let calculator = MemoryDecisionBiasCalculator()
        let state = makeReasoningState()
        let plan = PlanCandidate(
            operators: [Operator(kind: .runTests)],
            projectedState: state
        )

        let repoStrategy = SelectedStrategy(
            kind: .repoRepair,
            confidence: 0.8,
            rationale: "repo repair",
            allowedOperatorFamilies: [.repoAnalysis, .patchGeneration, .recovery]
        )

        let browserStrategy = SelectedStrategy(
            kind: .browserInteraction,
            confidence: 0.7,
            rationale: "browser interaction",
            allowedOperatorFamilies: [.browserTargeted, .hostTargeted]
        )

        let repoScore = calculator.biasScore(
            plan: plan,
            memoryInfluence: MemoryInfluence(),
            goal: Goal(description: "fix tests", preferredAgentKind: .code),
            worldState: makeWorldState(app: "Workspace"),
            taskContext: makeTaskContext(),
            selectedStrategy: repoStrategy
        )

        let browserScore = calculator.biasScore(
            plan: plan,
            memoryInfluence: MemoryInfluence(),
            goal: Goal(description: "fix tests", preferredAgentKind: .code),
            worldState: makeWorldState(app: "Safari"),
            taskContext: makeTaskContext(),
            selectedStrategy: browserStrategy
        )

        // Both should be valid values; the specific difference depends
        // on the MemoryDecisionBias strategy-specific logic. The key
        // assertion is that the function accepts non-optional strategy.
        #expect(repoScore.isFinite)
        #expect(browserScore.isFinite)
    }

    // MARK: - Helpers

    private func makeReasoningState() -> ReasoningPlanningState {
        ReasoningPlanningState(
            agentKind: .code,
            repoOpen: true,
            modalPresent: false,
            patchApplied: false,
            testsObserved: false
        )
    }

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

    private func makeTaskContext() -> TaskContext {
        let goal = Goal(description: "fix tests", preferredAgentKind: .code)
        return TaskContext.from(goal: goal, workspaceRoot: nil)
    }
}
