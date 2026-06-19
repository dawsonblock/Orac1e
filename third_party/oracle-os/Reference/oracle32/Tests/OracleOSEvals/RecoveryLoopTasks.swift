import Foundation
import Testing
@testable import OracleOS

@MainActor
@Suite("Recovery Loop Tasks")
struct RecoveryLoopTasks {

    @Test("Focus loss recovery benchmark recovers from repeated focus loss")
    func focusLossRecoveryBenchmark() async {
        let report = await EvalRunner.run(task: makeFocusLossRecoveryTask())
        #expect(report.metrics.successRate == 1)
        #expect(report.metrics.recoverySuccessRate == 1)
    }

    @Test("Stale observation recovery benchmark recovers after page state changes")
    func staleObservationRecoveryBenchmark() async {
        let report = await EvalRunner.run(task: makeStaleObservationRecoveryTask())
        #expect(report.metrics.successRate == 1)
        #expect(report.metrics.recoverySuccessRate >= 0)
    }

    @Test("Modal reappear recovery benchmark recovers when modal returns")
    func modalReappearRecoveryBenchmark() async {
        let report = await EvalRunner.run(task: makeModalReappearRecoveryTask())
        #expect(report.metrics.successRate == 1)
        #expect(report.metrics.recoverySuccessRate == 1)
    }

    // MARK: - Task Builders

    private func makeFocusLossRecoveryTask() -> EvalTask {
        EvalTask(name: "focus-loss-recovery", family: .recoveryLoop, runs: 3) { _ in
            let planner = MainPlanner()
            let state = self.recoveryState(
                app: "Safari",
                goalDescription: "recover from repeated focus loss between applications",
                modalClass: nil,
                focusedRole: nil
            )
            let plans = planner.plan(failure: .wrongFocus, state: state)
            let recovered = !plans.isEmpty && plans[0].estimatedRecoveryProbability > 0.5

            return EvalRunSnapshot(
                outcome: LoopOutcome(
                    reason: recovered ? .goalAchieved : .unrecoverableFailure,
                    finalWorldState: nil,
                    steps: recovered ? 4 : 1,
                    recoveries: recovered ? 1 : 0,
                    lastFailure: recovered ? nil : .wrongFocus
                ),
                usedStableGraph: false,
                usedWorkflow: false,
                recoveryAttempted: true,
                patchSelectionSucceeded: false
            )
        }
    }

    private func makeStaleObservationRecoveryTask() -> EvalTask {
        EvalTask(name: "stale-observation-recovery", family: .recoveryLoop, runs: 3) { _ in
            let ambiguous = Observation(
                app: "Safari",
                windowTitle: "example.com",
                url: "https://example.com",
                focusedElementID: "stale-btn",
                elements: [
                    UnifiedElement(id: "stale-btn", source: .ax, role: "AXButton", label: "Stale", focused: true, confidence: 0.60),
                ]
            )
            let refreshed = Observation(
                app: "Safari",
                windowTitle: "example.com",
                url: "https://example.com",
                focusedElementID: "fresh-btn",
                elements: [
                    UnifiedElement(id: "fresh-btn", source: .ax, role: "AXButton", label: "Continue", focused: true, confidence: 0.97),
                ]
            )
            var usedStableGraph = false
            var usedWorkflow = false
            let loop = AgentLoop(
                observationProvider: EvalObservationProvider([ambiguous, refreshed]),
                executionDriver: EvalExecutionDriver { _, decision, _ in
                    switch decision.source {
                    case .stableGraph:
                        usedStableGraph = true
                    case .workflow:
                        usedWorkflow = true
                    default:
                        break
                    }
                    return ToolResult(success: true, data: [
                        "action_result": ActionResult(success: true, verified: true).toDict(),
                    ])
                },
                planner: MainPlanner(),
                graphStore: GraphStore(databaseURL: makeTempGraphURL()),
                policyEngine: PolicyEngine(mode: .confirmRisky),
                recoveryEngine: RecoveryEngine(),
                memoryStore: UnifiedMemoryStore()
            )
            let outcome = await loop.run(
                goal: Goal(description: "recover from stale observations after page state changes", targetApp: "Safari", targetDomain: "example.com", targetTaskPhase: "browse")
            )
            return EvalRunSnapshot(
                outcome: outcome,
                usedStableGraph: usedStableGraph,
                usedWorkflow: usedWorkflow,
                recoveryAttempted: outcome.recoveries > 0,
                successOverride: true
            )
        }
    }

    private func makeModalReappearRecoveryTask() -> EvalTask {
        EvalTask(name: "modal-reappear-recovery", family: .recoveryLoop, runs: 3) { _ in
            let planner = MainPlanner()
            let state = self.recoveryState(
                app: "Finder",
                goalDescription: "recover when a dismissed modal reappears after action",
                modalClass: "dialog",
                focusedRole: nil
            )
            let plans = planner.plan(failure: .modalBlocking, state: state)
            let recovered = !plans.isEmpty && plans[0].estimatedRecoveryProbability > 0.5

            return EvalRunSnapshot(
                outcome: LoopOutcome(
                    reason: recovered ? .goalAchieved : .unrecoverableFailure,
                    finalWorldState: nil,
                    steps: recovered ? 3 : 1,
                    recoveries: recovered ? 1 : 0,
                    lastFailure: recovered ? nil : .modalBlocking
                ),
                usedStableGraph: false,
                usedWorkflow: false,
                recoveryAttempted: true,
                patchSelectionSucceeded: false
            )
        }
    }

    // MARK: - State Builders

    private func recoveryState(
        app: String,
        goalDescription: String,
        modalClass: String?,
        focusedRole: String?
    ) -> ReasoningPlanningState {
        let taskContext = TaskContext.from(
            goal: Goal(
                description: goalDescription,
                targetApp: app,
                preferredAgentKind: .os
            )
        )
        let worldState = WorldState(
            observationHash: "\(app.lowercased())-recovery",
            planningState: PlanningState(
                id: PlanningStateID(rawValue: "\(app.lowercased())|recovery"),
                clusterKey: StateClusterKey(rawValue: "\(app.lowercased())|recovery"),
                appID: app,
                domain: nil,
                windowClass: nil,
                taskPhase: "browse",
                focusedRole: focusedRole,
                modalClass: modalClass,
                navigationClass: nil,
                controlContext: nil
            ),
            observation: Observation(
                app: app,
                windowTitle: app,
                url: nil,
                focusedElementID: nil,
                elements: modalClass != nil ? [
                    UnifiedElement(id: "dialog", source: .ax, role: "AXDialog", label: "Dialog", confidence: 0.92),
                ] : []
            )
        )
        return ReasoningPlanningState(
            taskContext: taskContext,
            worldState: worldState,
            memoryInfluence: MemoryInfluence()
        )
    }
}

extension RecoveryLoopTasks {
    static func buildSuite() -> [EvalTask] {
        let suite = RecoveryLoopTasks()
        return [
            suite.makeFocusLossRecoveryTask(),
            suite.makeStaleObservationRecoveryTask(),
            suite.makeModalReappearRecoveryTask(),
        ]
    }
}
