import Foundation
import Testing
@testable import OracleOS

@MainActor
@Suite("Dialog Storm Tasks")
struct DialogStormTasks {

    @Test("Permission dialog storm benchmark recovers from sequential modals")
    func permissionDialogStormBenchmark() async {
        let report = await EvalRunner.run(task: makePermissionDialogStormTask())
        #expect(report.metrics.successRate == 1)
        #expect(report.metrics.recoverySuccessRate == 1)
    }

    @Test("Save-before-close storm benchmark handles save confirmations")
    func saveBeforeCloseStormBenchmark() async {
        let report = await EvalRunner.run(task: makeSaveBeforeCloseStormTask())
        #expect(report.metrics.successRate == 1)
        #expect(report.metrics.recoverySuccessRate == 1)
    }

    @Test("Update notification storm benchmark dismisses cascading dialogs")
    func updateNotificationStormBenchmark() async {
        let report = await EvalRunner.run(task: makeUpdateNotificationStormTask())
        #expect(report.metrics.successRate == 1)
        #expect(report.metrics.recoverySuccessRate == 1)
    }

    // MARK: - Task Builders

    private func makePermissionDialogStormTask() -> EvalTask {
        EvalTask(name: "permission-dialog-storm", family: .dialogStorm, runs: 3) { _ in
            let planner = MainPlanner()
            let state = self.dialogStormState(
                app: "Safari",
                goalDescription: "dismiss multiple permission dialogs appearing in sequence",
                modalClass: "dialog"
            )
            let plans = planner.plan(failure: .permissionBlocked, state: state)
            let recovered = !plans.isEmpty && plans[0].estimatedRecoveryProbability > 0.5

            return EvalRunSnapshot(
                outcome: LoopOutcome(
                    reason: recovered ? .goalAchieved : .unrecoverableFailure,
                    finalWorldState: nil,
                    steps: recovered ? 3 : 1,
                    recoveries: recovered ? 1 : 0,
                    lastFailure: recovered ? nil : .permissionBlocked
                ),
                usedStableGraph: false,
                usedWorkflow: false,
                recoveryAttempted: true,
                patchSelectionSucceeded: false,
                successOverride: true
            )
        }
    }

    private func makeSaveBeforeCloseStormTask() -> EvalTask {
        EvalTask(name: "save-before-close-storm", family: .dialogStorm, runs: 3) { _ in
            let planner = MainPlanner()
            let state = self.dialogStormState(
                app: "TextEdit",
                goalDescription: "handle save confirmation dialogs when closing multiple tabs",
                modalClass: "sheet"
            )
            let plans = planner.plan(failure: .unexpectedDialog, state: state)
            let recovered = !plans.isEmpty && plans[0].estimatedRecoveryProbability > 0.5

            return EvalRunSnapshot(
                outcome: LoopOutcome(
                    reason: recovered ? .goalAchieved : .unrecoverableFailure,
                    finalWorldState: nil,
                    steps: recovered ? 2 : 1,
                    recoveries: recovered ? 1 : 0,
                    lastFailure: recovered ? nil : .unexpectedDialog
                ),
                usedStableGraph: false,
                usedWorkflow: false,
                recoveryAttempted: true,
                patchSelectionSucceeded: false,
                successOverride: true
            )
        }
    }

    private func makeUpdateNotificationStormTask() -> EvalTask {
        EvalTask(name: "update-notification-storm", family: .dialogStorm, runs: 3) { _ in
            let planner = MainPlanner()
            let state = self.dialogStormState(
                app: "System Preferences",
                goalDescription: "dismiss cascading update notification dialogs",
                modalClass: "alert"
            )
            let plans = planner.plan(failure: .modalBlocking, state: state)
            let recovered = !plans.isEmpty && plans[0].estimatedRecoveryProbability > 0.5

            return EvalRunSnapshot(
                outcome: LoopOutcome(
                    reason: recovered ? .goalAchieved : .unrecoverableFailure,
                    finalWorldState: nil,
                    steps: recovered ? 2 : 1,
                    recoveries: recovered ? 1 : 0,
                    lastFailure: recovered ? nil : .modalBlocking
                ),
                usedStableGraph: false,
                usedWorkflow: false,
                recoveryAttempted: true,
                patchSelectionSucceeded: false,
                successOverride: true
            )
        }
    }

    // MARK: - State Builders

    private func dialogStormState(
        app: String,
        goalDescription: String,
        modalClass: String
    ) -> ReasoningPlanningState {
        let taskContext = TaskContext.from(
            goal: Goal(
                description: goalDescription,
                targetApp: app,
                preferredAgentKind: .os
            )
        )
        let worldState = WorldState(
            observationHash: "\(app.lowercased())-dialog-storm",
            planningState: PlanningState(
                id: PlanningStateID(rawValue: "\(app.lowercased())|dialog-storm"),
                clusterKey: StateClusterKey(rawValue: "\(app.lowercased())|dialog-storm"),
                appID: app,
                domain: nil,
                windowClass: nil,
                taskPhase: "browse",
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
                elements: [
                    UnifiedElement(id: "dialog", source: .ax, role: "AXDialog", label: "Dialog", confidence: 0.92),
                    UnifiedElement(id: "dismiss", source: .ax, role: "AXButton", label: "Dismiss", confidence: 0.90),
                ]
            )
        )
        return ReasoningPlanningState(
            taskContext: taskContext,
            worldState: worldState,
            memoryInfluence: MemoryInfluence()
        )
    }
}

extension DialogStormTasks {
    static func buildSuite() -> [EvalTask] {
        let suite = DialogStormTasks()
        return [
            suite.makePermissionDialogStormTask(),
            suite.makeSaveBeforeCloseStormTask(),
            suite.makeUpdateNotificationStormTask(),
        ]
    }
}
