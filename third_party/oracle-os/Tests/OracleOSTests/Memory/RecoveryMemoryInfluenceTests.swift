import Foundation
import Testing
@testable import OracleOS

@Suite("Recovery Memory Influence")
struct RecoveryMemoryInfluenceTests {

    @Test("Memory influence provides preferred recovery strategy")
    func memoryInfluenceProvidesPreferredRecoveryStrategy() {
        let influence = MemoryInfluence(preferredRecoveryStrategy: "dismiss_modal")
        #expect(influence.preferredRecoveryStrategy == "dismiss_modal")
    }

    @Test("Memory influence risk penalty is non-negative")
    func memoryInfluenceRiskPenaltyNonNegative() {
        let influence = MemoryInfluence(riskPenalty: 0.15)
        #expect(influence.riskPenalty >= 0)
    }

    @Test("Recovery planner generates plans for modal blocking")
    func recoveryPlannerGeneratesPlansForModalBlocking() {
        let planner = MainPlanner()
        let state = makeReasoningState(modalPresent: true)
        let plans = planner.plan(failure: .modalBlocking, state: state)
        #expect(!plans.isEmpty)
        #expect(plans.first?.recoveryOperators.first?.kind == .dismissModal)
    }

    @Test("Recovery planner generates plans for wrong focus")
    func recoveryPlannerGeneratesPlansForWrongFocus() {
        let planner = MainPlanner()
        let state = makeReasoningState(targetApp: "Safari")
        let plans = planner.plan(failure: .wrongFocus, state: state)
        #expect(!plans.isEmpty)
    }

    @Test("Recovery planner returns empty for unsupported failure classes")
    func recoveryPlannerReturnsEmptyForUnsupported() {
        let planner = MainPlanner()
        let state = makeReasoningState()
        let plans = planner.plan(failure: .workspaceScopeViolation, state: state)
        #expect(plans.isEmpty)
    }

    private func makeReasoningState(
        modalPresent: Bool = false,
        targetApp: String? = nil
    ) -> ReasoningPlanningState {
        var state = ReasoningPlanningState(
            taskContext: TaskContext(
                goal: Goal(description: "test recovery", preferredAgentKind: .os),
                agentKind: .os,
                workspaceRoot: nil,
                phases: [.operatingSystem]
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
        if let targetApp {
            state.targetApplication = targetApp
        }
        return state
    }
}
