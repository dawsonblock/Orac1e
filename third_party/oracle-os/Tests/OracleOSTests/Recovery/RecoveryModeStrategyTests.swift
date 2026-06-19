import Foundation
import Testing
@testable import OracleOS

@Suite("Recovery Mode as Strategy")
struct RecoveryModeStrategyTests {

    @Test("StrategySelector selects recovery for repeated failures")
    func strategySelectorRecoveryForRepeatedFailures() {
        let selector = StrategySelector()
        let goal = Goal(description: "do something", preferredAgentKind: .mixed)
        let worldState = makeWorldState(app: "App")

        let strategy = selector.selectStrategy(
            goal: goal,
            worldState: worldState,
            memoryInfluence: MemoryInfluence(),
            workflowIndex: WorkflowIndex(),
            agentKind: .mixed,
            recentFailureCount: 5
        )

        #expect(strategy.kind == .recoveryMode)
    }

    @Test("Recovery strategy only allows recovery + graphEdge families")
    func recoveryFamiliesAreBounded() {
        let families = StrategyLibrary.allowedFamilies(for: .recoveryMode)

        #expect(families.contains(.recovery))
        #expect(families.contains(.graphEdge))

        // Must NOT contain production operator families
        #expect(!families.contains(.browserTargeted))
        #expect(!families.contains(.repoAnalysis))
        #expect(!families.contains(.patchGeneration))
        #expect(!families.contains(.patchExperiment))
        #expect(!families.contains(.llmProposal))
    }

    @Test("Plans generated during recovery only use recovery operators")
    func recoveryPlansUseBoundedFamilies() {
        let state = makeReasoningState()

        let recoveryStrategy = SelectedStrategy(
            kind: .recoveryMode,
            confidence: 0.9,
            rationale: "recovery",
            allowedOperatorFamilies: Array(StrategyLibrary.allowedFamilies(for: .recoveryMode))
        )

        // Recovery plan → should be allowed
        let recoveryPlan = PlanCandidate(
            operators: [Operator(kind: .dismissModal), Operator(kind: .retryWithAlternateTarget)],
            projectedState: state
        )
        #expect(recoveryPlan.isAllowed(by: recoveryStrategy))

        // Repo plan → should NOT be allowed under recovery
        let repoPlan = PlanCandidate(
            operators: [Operator(kind: .runTests), Operator(kind: .applyPatch)],
            projectedState: state
        )
        #expect(!repoPlan.isAllowed(by: recoveryStrategy))

        // Browser plan → should NOT be allowed under recovery
        let browserPlan = PlanCandidate(
            operators: [Operator(kind: .navigateBrowser), Operator(kind: .clickTarget)],
            projectedState: state
        )
        #expect(!browserPlan.isAllowed(by: recoveryStrategy))
    }

    @Test("StrategySelector selects recovery for modal conditions")
    func strategySelectorRecoveryForModal() {
        let selector = StrategySelector()
        let goal = Goal(description: "submit form", preferredAgentKind: .os)
        let worldState = makeWorldState(app: "Safari", modalClass: "dialog")

        let strategy = selector.selectStrategy(
            goal: goal,
            worldState: worldState,
            memoryInfluence: MemoryInfluence(),
            workflowIndex: WorkflowIndex(),
            agentKind: .os
        )

        #expect(strategy.kind == .recoveryMode)
        #expect(!strategy.allowedOperatorFamilies.isEmpty)
    }

    @Test("Recovery mode reevaluates after bounded steps")
    func recoveryReevaluationBounded() {
        let evaluator = StrategyEvaluator()
        let strategy = SelectedStrategy(
            kind: .recoveryMode,
            confidence: 0.9,
            rationale: "recovery mode",
            allowedOperatorFamilies: Array(StrategyLibrary.allowedFamilies(for: .recoveryMode)),
            reevaluateAfterStepCount: 3
        )
        evaluator.setCurrentStrategy(strategy)

        // Should not reevaluate before threshold
        evaluator.recordStep()
        evaluator.recordStep()
        #expect(evaluator.shouldReevaluate() == nil)

        // Should reevaluate at threshold
        evaluator.recordStep()
        let cause = evaluator.shouldReevaluate()
        #expect(cause == .stepThresholdReached)
    }

    // MARK: - Helpers

    private func makeReasoningState() -> ReasoningPlanningState {
        ReasoningPlanningState(
            agentKind: .os,
            repoOpen: false,
            modalPresent: true,
            patchApplied: false,
            testsObserved: false
        )
    }

    private func makeWorldState(app: String, modalClass: String? = nil) -> WorldState {
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
                modalClass: modalClass,
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
