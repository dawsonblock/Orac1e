import Foundation
import Testing
@testable import OracleOS

@Suite("Recovery Planner")
struct RecoveryPlannerTests {

    @Test("Recovery planner produces plans for modal blocking")
    func producesPlansForModalBlocking() {
        let planner = MainPlanner()
        let state = makeState(modalPresent: true)
        let plans = planner.plan(failure: .modalBlocking, state: state)
        #expect(!plans.isEmpty)
        #expect(plans.first?.recoveryOperators.contains { $0.kind == .dismissModal } == true)
    }

    @Test("Recovery planner produces plans for wrong focus")
    func producesPlansForWrongFocus() {
        let planner = MainPlanner()
        let state = makeState(targetApp: "Safari")
        let plans = planner.plan(failure: .wrongFocus, state: state)
        #expect(!plans.isEmpty)
    }

    @Test("Recovery planner produces plans for patch failure")
    func producesPlansForPatchFailure() {
        let planner = MainPlanner()
        let state = makeState(patchApplied: true)
        let plans = planner.plan(failure: .patchApplyFailed, state: state)
        #expect(!plans.isEmpty)
        #expect(plans.first?.recoveryOperators.contains { $0.kind == .rollbackPatch || $0.kind == .revertPatch } == true)
    }

    @Test("Recovery plans are sorted by probability descending")
    func plansSortedByProbabilityDescending() {
        let planner = MainPlanner()
        let state = makeState(targetApp: "Safari")
        let plans = planner.plan(failure: .wrongFocus, state: state)
        for i in 0..<max(plans.count - 1, 0) {
            #expect(plans[i].estimatedRecoveryProbability >= plans[i + 1].estimatedRecoveryProbability)
        }
    }

    @Test("Best recovery plan returns highest probability plan")
    func bestPlanReturnsHighestProbability() {
        let planner = MainPlanner()
        let state = makeState(modalPresent: true)
        let best = planner.bestRecoveryPlan(failure: .modalBlocking, state: state)
        let all = planner.plan(failure: .modalBlocking, state: state)
        #expect(best?.estimatedRecoveryProbability == all.first?.estimatedRecoveryProbability)
    }

    @Test("Recovery strategy library returns entries for common failures")
    func strategyLibraryReturnsEntries() {
        let library = RecoveryStrategyLibrary.shared
        let modalEntries = library.applicable(for: .modalBlocking)
        #expect(!modalEntries.isEmpty)
        let targetEntries = library.applicable(for: .targetMissing)
        #expect(!targetEntries.isEmpty)
    }

    @Test("Recovery operator defaults cover major failure classes")
    func recoveryOperatorDefaultsCoverMajorFailures() {
        let modalOps = RecoveryOperator.applicable(for: .modalBlocking)
        #expect(!modalOps.isEmpty)
        let targetOps = RecoveryOperator.applicable(for: .targetMissing)
        #expect(!targetOps.isEmpty)
        let patchOps = RecoveryOperator.applicable(for: .patchApplyFailed)
        #expect(!patchOps.isEmpty)
    }

    private func makeState(
        modalPresent: Bool = false,
        targetApp: String? = nil,
        patchApplied: Bool = false
    ) -> ReasoningPlanningState {
        let agentKind: AgentKind = patchApplied ? .code : .os
        var state = ReasoningPlanningState(
            taskContext: TaskContext(
                goal: Goal(description: "recovery test", preferredAgentKind: agentKind),
                agentKind: agentKind,
                workspaceRoot: patchApplied ? "/tmp/workspace" : nil,
                phases: patchApplied ? [.engineering] : [.operatingSystem]
            ),
            worldState: WorldState(
                observationHash: "test",
                planningState: PlanningState(
                    id: PlanningStateID(rawValue: "test"),
                    clusterKey: StateClusterKey(rawValue: "test"),
                    appID: targetApp ?? "Unknown",
                    domain: nil,
                    windowClass: nil,
                    taskPhase: "browse",
                    focusedRole: nil,
                    modalClass: modalPresent ? "dialog" : nil,
                    navigationClass: nil,
                    controlContext: nil
                ),
                observation: Observation(app: targetApp, windowTitle: nil, url: nil, focusedElementID: nil, elements: [])
            ),
            memoryInfluence: MemoryInfluence()
        )
        if let targetApp { state.targetApplication = targetApp }
        if patchApplied { state.patchApplied = true }
        return state
    }
}
