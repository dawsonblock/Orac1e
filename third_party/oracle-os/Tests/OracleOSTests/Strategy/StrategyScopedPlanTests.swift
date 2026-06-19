import Foundation
import Testing
@testable import OracleOS

@Suite("Strategy-Scoped Plan Filtering")
struct StrategyScopedPlanTests {

    @Test("PlanCandidate computes operator families from operators")
    func planCandidateComputesFamilies() {
        let state = makeReasoningState()
        let plan = PlanCandidate(
            operators: [Operator(kind: .runTests), Operator(kind: .applyPatch)],
            projectedState: state
        )
        #expect(plan.operatorFamilies.contains(.repoAnalysis))
        #expect(plan.operatorFamilies.contains(.patchGeneration))
    }

    @Test("PlanCandidate isAllowed checks against strategy")
    func planCandidateIsAllowed() {
        let state = makeReasoningState()

        let repoRepairStrategy = SelectedStrategy(
            kind: .repoRepair,
            confidence: 0.8,
            rationale: "test",
            allowedOperatorFamilies: [.repoAnalysis, .patchGeneration, .recovery]
        )

        // Plan with repo operators — should be allowed
        let repoPlan = PlanCandidate(
            operators: [Operator(kind: .runTests), Operator(kind: .applyPatch)],
            projectedState: state
        )
        #expect(repoPlan.isAllowed(by: repoRepairStrategy))

        // Plan with browser operators — should NOT be allowed
        let browserPlan = PlanCandidate(
            operators: [Operator(kind: .navigateBrowser)],
            projectedState: state
        )
        #expect(!browserPlan.isAllowed(by: repoRepairStrategy))
    }

    @Test("ReasoningOperatorKind maps to correct operator families")
    func operatorKindMapsToFamily() {
        #expect(ReasoningOperatorKind.runTests.operatorFamily == .repoAnalysis)
        #expect(ReasoningOperatorKind.buildProject.operatorFamily == .repoAnalysis)
        #expect(ReasoningOperatorKind.applyPatch.operatorFamily == .patchGeneration)
        #expect(ReasoningOperatorKind.revertPatch.operatorFamily == .patchGeneration)
        #expect(ReasoningOperatorKind.dismissModal.operatorFamily == .recovery)
        #expect(ReasoningOperatorKind.clickTarget.operatorFamily == .browserTargeted)
        #expect(ReasoningOperatorKind.navigateBrowser.operatorFamily == .browserTargeted)
        #expect(ReasoningOperatorKind.openApplication.operatorFamily == .hostTargeted)
        #expect(ReasoningOperatorKind.focusWindow.operatorFamily == .hostTargeted)
        #expect(ReasoningOperatorKind.restartApplication.operatorFamily == .hostTargeted)
        #expect(ReasoningOperatorKind.retryWithAlternateTarget.operatorFamily == .recovery)
        #expect(ReasoningOperatorKind.rollbackPatch.operatorFamily == .patchGeneration)
        #expect(ReasoningOperatorKind.rerunTests.operatorFamily == .repoAnalysis)
    }

    @Test("Graph navigator classifies actions into operator families")
    func graphNavigatorClassifiesActions() {
        #expect(LedgerNavigator.operatorFamilyForAction("run_tests") == .repoAnalysis)
        #expect(LedgerNavigator.operatorFamilyForAction("build_project") == .repoAnalysis)
        #expect(LedgerNavigator.operatorFamilyForAction("apply_patch") == .patchGeneration)
        #expect(LedgerNavigator.operatorFamilyForAction("navigate_browser") == .browserTargeted)
        #expect(LedgerNavigator.operatorFamilyForAction("dismiss_modal") == .recovery)
        #expect(LedgerNavigator.operatorFamilyForAction("open_application") == .hostTargeted)
        #expect(LedgerNavigator.operatorFamilyForAction("unknown_action") == .graphEdge)
    }

    @Test("TaskStrategyKind maps to correct StrategyKind")
    func taskStrategyKindMaps() {
        #expect(TaskStrategyKind.workflowReuse.strategyKind == .workflowExecution)
        #expect(TaskStrategyKind.codeRepair.strategyKind == .repoRepair)
        #expect(TaskStrategyKind.uiExploration.strategyKind == .browserInteraction)
        #expect(TaskStrategyKind.recovery.strategyKind == .recoveryMode)
        #expect(TaskStrategyKind.navigation.strategyKind == .graphNavigation)
        #expect(TaskStrategyKind.configurationDiagnosis.strategyKind == .diagnosticAnalysis)
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
}
