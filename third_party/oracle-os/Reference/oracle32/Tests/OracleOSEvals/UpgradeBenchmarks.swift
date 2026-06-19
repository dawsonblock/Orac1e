import Foundation
import Testing
@testable import OracleOS

@MainActor
@Suite("Upgrade Benchmarks")
struct UpgradeBenchmarks {

    @Test("Multi-step planning benchmark generates bounded plans")
    func multiStepPlanningBenchmark() async {
        let report = await EvalRunner.run(task: makeMultiStepPlanningTask())
        #expect(report.metrics.successRate == 1)
        #expect(report.metrics.averageSteps >= 1)
    }

    @Test("Recovery planning benchmark handles modal failure")
    func recoveryPlanningBenchmark() async {
        let report = await EvalRunner.run(task: makeRecoveryPlanningTask())
        #expect(report.metrics.successRate == 1)
        #expect(report.metrics.recoverySuccessRate == 1)
    }

    @Test("Workflow reuse benchmark detects workflow replay")
    func workflowReuseBenchmark() async {
        let report = await EvalRunner.run(task: makeWorkflowReuseTask())
        #expect(report.metrics.successRate == 1)
        #expect(report.metrics.workflowReuseRatio == 1)
    }

    private func makeMultiStepPlanningTask() -> EvalTask {
        EvalTask(name: "multi-step-planning", family: .codingTask, runs: 3) { _ in
            let engine = ReasoningEngine(maxDepth: 3, maxPlans: 5)
            let state = self.codeReasoningState()
            let plans = engine.generatePlans(from: state)
            let goalAchieved = !plans.isEmpty && plans.allSatisfy { $0.operators.count <= 3 }

            return EvalRunSnapshot(
                outcome: LoopOutcome(
                    reason: goalAchieved ? .goalAchieved : .noViablePlan,
                    finalWorldState: nil,
                    steps: plans.count,
                    recoveries: 0
                ),
                usedStableGraph: false,
                usedWorkflow: false,
                recoveryAttempted: false,
                patchSelectionSucceeded: false
            )
        }
    }

    private func makeRecoveryPlanningTask() -> EvalTask {
        EvalTask(name: "recovery-planning", family: .operatorTask, runs: 3) { _ in
            let planner = MainPlanner()
            let state = self.modalReasoningState()
            let plans = planner.plan(failure: .modalBlocking, state: state)
            let recovered = !plans.isEmpty && plans[0].estimatedRecoveryProbability > 0.5

            return EvalRunSnapshot(
                outcome: LoopOutcome(
                    reason: recovered ? .goalAchieved : .unrecoverableFailure,
                    finalWorldState: nil,
                    steps: 1,
                    recoveries: recovered ? 1 : 0
                ),
                usedStableGraph: false,
                usedWorkflow: false,
                recoveryAttempted: true,
                patchSelectionSucceeded: false
            )
        }
    }

    private func makeWorkflowReuseTask() -> EvalTask {
        EvalTask(name: "workflow-reuse", family: .operatorTask, runs: 3) { _ in
            let confidenceModel = WorkflowConfidenceModel()
            let workflow = WorkflowPlan(
                agentKind: .os,
                goalPattern: "open compose",
                steps: [],
                successRate: 0.95,
                repeatedTraceSegmentCount: 8,
                replayValidationSuccess: 0.9,
                promotionStatus: .promoted,
                lastSucceededAt: Date()
            )
            let confidence = confidenceModel.confidence(for: workflow)
            let reliable = confidenceModel.isReliable(workflow)

            return EvalRunSnapshot(
                outcome: LoopOutcome(
                    reason: reliable ? .goalAchieved : .noViablePlan,
                    finalWorldState: nil,
                    steps: 1,
                    recoveries: 0
                ),
                usedStableGraph: false,
                usedWorkflow: reliable,
                recoveryAttempted: false,
                patchSelectionSucceeded: false
            )
        }
    }

    private func codeReasoningState() -> ReasoningPlanningState {
        let taskContext = TaskContext.from(
            goal: Goal(
                description: "fix failing tests in repository",
                workspaceRoot: "/tmp/workspace",
                preferredAgentKind: .code
            ),
            workspaceRoot: URL(fileURLWithPath: "/tmp/workspace", isDirectory: true)
        )
        let worldState = WorldState(
            observationHash: "workspace",
            planningState: PlanningState(
                id: PlanningStateID(rawValue: "workspace|dirty"),
                clusterKey: StateClusterKey(rawValue: "workspace|dirty"),
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
            )
        )
        return ReasoningPlanningState(
            taskContext: taskContext,
            worldState: worldState,
            memoryInfluence: MemoryInfluence(preferredFixPath: "Sources/Foo.swift")
        )
    }

    private func modalReasoningState() -> ReasoningPlanningState {
        let taskContext = TaskContext.from(
            goal: Goal(
                description: "dismiss modal and continue",
                targetApp: "Safari",
                preferredAgentKind: .os
            )
        )
        let worldState = WorldState(
            observationHash: "safari-modal",
            planningState: PlanningState(
                id: PlanningStateID(rawValue: "safari|dialog"),
                clusterKey: StateClusterKey(rawValue: "safari|dialog"),
                appID: "Safari",
                domain: nil,
                windowClass: nil,
                taskPhase: "browse",
                focusedRole: nil,
                modalClass: "dialog",
                navigationClass: nil,
                controlContext: nil
            ),
            observation: Observation(
                app: "Safari",
                windowTitle: "Safari",
                url: "https://example.com",
                focusedElementID: nil,
                elements: [
                    UnifiedElement(id: "dialog", source: .ax, role: "AXDialog", label: "Dialog", confidence: 0.9),
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

extension UpgradeBenchmarks {
    static func buildSuite() -> [EvalTask] {
        let suite = UpgradeBenchmarks()
        return [
            suite.makeMultiStepPlanningTask(),
            suite.makeRecoveryPlanningTask(),
            suite.makeWorkflowReuseTask(),
        ]
    }
}
