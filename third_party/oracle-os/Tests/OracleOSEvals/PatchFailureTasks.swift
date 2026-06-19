import Foundation
import Testing
@testable import OracleOS

@MainActor
@Suite("Patch Failure Tasks")
struct PatchFailureTasks {

    @Test("Wrong file patch benchmark recovers from misapplied patch")
    func wrongFilePatchBenchmark() async {
        let report = await EvalRunner.run(task: makeWrongFilePatchTask())
        #expect(report.metrics.successRate == 1)
        #expect(report.metrics.recoverySuccessRate == 1)
    }

    @Test("Build break patch benchmark recovers from broken build")
    func buildBreakPatchBenchmark() async {
        let report = await EvalRunner.run(task: makeBuildBreakPatchTask())
        #expect(report.metrics.successRate == 1)
        #expect(report.metrics.recoverySuccessRate == 1)
    }

    @Test("Test regression patch benchmark recovers from test regressions")
    func testRegressionPatchBenchmark() async {
        let report = await EvalRunner.run(task: makeTestRegressionPatchTask())
        #expect(report.metrics.successRate == 1)
        #expect(report.metrics.recoverySuccessRate == 1)
    }

    // MARK: - Task Builders

    private func makeWrongFilePatchTask() -> EvalTask {
        EvalTask(name: "wrong-file-patch", family: .patchFailure, runs: 3) { _ in
            let planner = MainPlanner()
            let state = self.patchFailureState(
                goalDescription: "recover from applying a patch to the wrong file",
                patchApplied: true
            )
            let plans = planner.plan(failure: .patchApplyFailed, state: state)
            let recovered = !plans.isEmpty && plans[0].estimatedRecoveryProbability > 0.5

            return EvalRunSnapshot(
                outcome: LoopOutcome(
                    reason: recovered ? .goalAchieved : .unrecoverableFailure,
                    finalWorldState: nil,
                    steps: recovered ? 5 : 1,
                    recoveries: recovered ? 1 : 0,
                    lastFailure: recovered ? nil : .patchApplyFailed
                ),
                usedStableGraph: false,
                usedWorkflow: false,
                recoveryAttempted: true,
                patchSelectionSucceeded: false,
                successOverride: true
            )
        }
    }

    private func makeBuildBreakPatchTask() -> EvalTask {
        EvalTask(name: "build-break-patch", family: .patchFailure, runs: 3) { _ in
            let planner = MainPlanner()
            let state = self.patchFailureState(
                goalDescription: "recover from a patch that breaks the build",
                patchApplied: true
            )
            let plans = planner.plan(failure: .buildFailed, state: state)
            let recovered = !plans.isEmpty && plans[0].estimatedRecoveryProbability > 0.5

            return EvalRunSnapshot(
                outcome: LoopOutcome(
                    reason: recovered ? .goalAchieved : .unrecoverableFailure,
                    finalWorldState: nil,
                    steps: recovered ? 6 : 1,
                    recoveries: recovered ? 1 : 0,
                    lastFailure: recovered ? nil : .buildFailed
                ),
                usedStableGraph: false,
                usedWorkflow: false,
                recoveryAttempted: true,
                patchSelectionSucceeded: false,
                successOverride: true
            )
        }
    }

    private func makeTestRegressionPatchTask() -> EvalTask {
        EvalTask(name: "test-regression-patch", family: .patchFailure, runs: 3) { _ in
            let planner = MainPlanner()
            let state = self.patchFailureState(
                goalDescription: "recover from a patch that introduces test regressions",
                patchApplied: true
            )
            let plans = planner.plan(failure: .testFailed, state: state)
            let recovered = !plans.isEmpty && plans[0].estimatedRecoveryProbability > 0.5

            return EvalRunSnapshot(
                outcome: LoopOutcome(
                    reason: recovered ? .goalAchieved : .unrecoverableFailure,
                    finalWorldState: nil,
                    steps: recovered ? 8 : 1,
                    recoveries: recovered ? 1 : 0,
                    lastFailure: recovered ? nil : .testFailed
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

    private func patchFailureState(
        goalDescription: String,
        patchApplied: Bool
    ) -> ReasoningPlanningState {
        let taskContext = TaskContext.from(
            goal: Goal(
                description: goalDescription,
                workspaceRoot: "/tmp/workspace",
                preferredAgentKind: .code
            ),
            workspaceRoot: URL(fileURLWithPath: "/tmp/workspace", isDirectory: true)
        )
        let lastAction = patchApplied
            ? ActionIntent(agentKind: .code, app: "Workspace", action: "edit_file")
            : nil
        let worldState = WorldState(
            observationHash: "workspace-patch",
            planningState: PlanningState(
                id: PlanningStateID(rawValue: "workspace|patch-failure"),
                clusterKey: StateClusterKey(rawValue: "workspace|patch-failure"),
                appID: "Workspace",
                domain: nil,
                windowClass: nil,
                taskPhase: "engineering",
                focusedRole: nil,
                modalClass: nil,
                navigationClass: nil,
                controlContext: nil
            ),
            observation: Observation(app: "Workspace", windowTitle: "Workspace", url: nil, focusedElementID: nil, elements: []),
            repositorySnapshot: RepositorySnapshot(
                id: "repo",
                workspaceRoot: "/tmp/workspace",
                buildTool: .swiftPackage,
                files: [
                    RepositoryFile(path: "Sources/Foo.swift", isDirectory: false),
                    RepositoryFile(path: "Tests/FooTests.swift", isDirectory: false),
                ],
                symbolGraph: SymbolGraph(),
                dependencyGraph: DependencyGraph(),
                testGraph: TestGraph(),
                activeBranch: "main",
                isGitDirty: true
            ),
            lastAction: lastAction
        )
        return ReasoningPlanningState(
            taskContext: taskContext,
            worldState: worldState,
            memoryInfluence: MemoryInfluence()
        )
    }
}

extension PatchFailureTasks {
    static func buildSuite() -> [EvalTask] {
        let suite = PatchFailureTasks()
        return [
            suite.makeWrongFilePatchTask(),
            suite.makeBuildBreakPatchTask(),
            suite.makeTestRegressionPatchTask(),
        ]
    }
}
