import Foundation
import Testing
@testable import OracleOS

@Suite("Plan Evaluator")
struct PlanEvaluatorTests {

    @Test("Plan evaluator scores plans with all components")
    func evaluatorScoresPlansWithAllComponents() {
        let evaluator = PlanEvaluator(workflowRetriever: WorkflowRetriever())
        let goal = Goal(
            description: "dismiss modal and click Continue",
            targetApp: "Safari",
            preferredAgentKind: .os
        )
        let taskContext = TaskContext.from(goal: goal)
        let worldState = WorldState(
            observationHash: "safari-modal",
            planningState: planningState(
                id: "safari|dialog",
                appID: "Safari",
                domain: nil,
                taskPhase: "browse",
                modalClass: "dialog"
            ),
            observation: Observation(
                app: "Safari",
                windowTitle: "Safari",
                url: "https://example.com",
                focusedElementID: nil,
                elements: [
                    UnifiedElement(id: "dialog", source: .ax, role: "AXDialog", label: "Dialog", confidence: 0.9),
                    UnifiedElement(id: "continue", source: .ax, role: "AXButton", label: "Continue", confidence: 0.9),
                ]
            )
        )

        let memoryInfluence = MemoryInfluence()
        let state = ReasoningPlanningState(
            taskContext: taskContext,
            worldState: worldState,
            memoryInfluence: memoryInfluence
        )

        let dismissPlan = PlanCandidate(
            operators: [Operator(kind: .dismissModal)],
            projectedState: Operator(kind: .dismissModal).effect(state)
        )
        let clickPlan = PlanCandidate(
            operators: [Operator(kind: .clickTarget)],
            projectedState: Operator(kind: .clickTarget).effect(state)
        )

        let scored = evaluator.evaluate(
            plans: [dismissPlan, clickPlan],
            taskContext: taskContext,
            goal: goal,
            worldState: worldState,
            graphStore: GraphStore(databaseURL: makeTempGraphURL()),
            workflowIndex: WorkflowIndex(),
            memoryStore: UnifiedMemoryStore()
        )

        #expect(scored.count == 2)
        #expect(scored.first?.score ?? 0 > 0)
    }

    @Test("Plan evaluator returns plans sorted by score descending")
    func evaluatorReturnsPlansSortedByScoreDescending() {
        let evaluator = PlanEvaluator(workflowRetriever: WorkflowRetriever())
        let goal = Goal(
            description: "run tests and fix code",
            workspaceRoot: "/tmp/workspace",
            preferredAgentKind: .code
        )
        let taskContext = TaskContext.from(
            goal: goal,
            workspaceRoot: URL(fileURLWithPath: "/tmp/workspace", isDirectory: true)
        )
        let worldState = WorldState(
            observationHash: "workspace",
            planningState: planningState(
                id: "workspace|dirty",
                appID: "Workspace",
                domain: nil,
                taskPhase: "engineering",
                modalClass: nil
            ),
            observation: Observation(app: "Workspace", windowTitle: "Workspace", url: nil, focusedElementID: nil, elements: []),
            repositorySnapshot: RepositorySnapshot(
                id: "repo",
                workspaceRoot: "/tmp/workspace",
                buildTool: .swiftPackage,
                files: [RepositoryFile(path: "Sources/Calculator.swift", isDirectory: false)],
                symbolGraph: SymbolGraph(),
                dependencyGraph: DependencyGraph(),
                testGraph: TestGraph(),
                activeBranch: "main",
                isGitDirty: true
            )
        )

        let state = ReasoningPlanningState(
            taskContext: taskContext,
            worldState: worldState,
            memoryInfluence: MemoryInfluence()
        )

        let plans = ReasoningEngine().generatePlans(from: state)
        guard plans.count >= 2 else { return }

        let scored = evaluator.evaluate(
            plans: plans,
            taskContext: taskContext,
            goal: goal,
            worldState: worldState,
            graphStore: GraphStore(databaseURL: makeTempGraphURL()),
            workflowIndex: WorkflowIndex(),
            memoryStore: UnifiedMemoryStore()
        )

        for i in 0..<max(scored.count - 1, 0) {
            #expect(scored[i].score >= scored[i + 1].score)
        }
    }

    @Test("Choose best plan respects minimum score threshold")
    func chooseBestPlanRespectsMinimumScore() {
        let evaluator = PlanEvaluator(workflowRetriever: WorkflowRetriever())
        let state = ReasoningPlanningState(
            taskContext: TaskContext(
                goal: Goal(description: "test", preferredAgentKind: .os),
                agentKind: .os,
                workspaceRoot: nil,
                phases: [.operatingSystem]
            ),
            worldState: WorldState(
                observationHash: "empty",
                planningState: planningState(
                    id: "empty",
                    appID: "Unknown",
                    domain: nil,
                    taskPhase: "browse",
                    modalClass: nil
                ),
                observation: Observation(app: nil, windowTitle: nil, url: nil, focusedElementID: nil, elements: [])
            ),
            memoryInfluence: MemoryInfluence()
        )

        let lowScorePlan = PlanCandidate(
            operators: [Operator(kind: .clickTarget)],
            projectedState: state,
            score: 0.1
        )

        let result = evaluator.chooseBestPlan([lowScorePlan], minimumScore: 0.6)
        #expect(result == nil)
    }

    @Test("PlanScore captures all scoring components")
    func planScoreCapturesComponents() {
        let score = PlanScore(
            predictedSuccess: 0.4,
            workflowMatch: 0.25,
            stableGraphSupport: 0.15,
            memoryBias: 0.05,
            riskPenalty: 0.1,
            costPenalty: 0.08,
            sourceType: .workflow,
            notes: ["test"]
        )

        #expect(score.total > 0)
        #expect(score.sourceType == .workflow)
        let expectedTotal = 0.4 + 0.25 + 0.15 + 0.05 - 0.1 - 0.08
        #expect(abs(score.total - expectedTotal) < 0.001)
    }


    @Test("PlanCandidate preserves source type through evaluation")
    func planCandidatePreservesSourceType() {
        let evaluator = PlanEvaluator(workflowRetriever: WorkflowRetriever())
        let goal = Goal(description: "open app", targetApp: "Safari", preferredAgentKind: .os)
        let taskContext = TaskContext.from(goal: goal)
        let worldState = WorldState(
            observationHash: "test",
            planningState: planningState(id: "test", appID: "Safari", domain: nil, taskPhase: "browse", modalClass: nil),
            observation: Observation(app: "Safari", windowTitle: "Safari", url: nil, focusedElementID: nil, elements: [])
        )
        let state = ReasoningPlanningState(
            taskContext: taskContext,
            worldState: worldState,
            memoryInfluence: MemoryInfluence()
        )

        let workflowPlan = PlanCandidate(
            operators: [Operator(kind: .openApplication)],
            projectedState: state,
            sourceType: .workflow
        )
        let graphPlan = PlanCandidate(
            operators: [Operator(kind: .openApplication)],
            projectedState: state,
            sourceType: .stableGraph
        )

        let scored = evaluator.evaluate(
            plans: [workflowPlan, graphPlan],
            taskContext: taskContext,
            goal: goal,
            worldState: worldState,
            graphStore: GraphStore(databaseURL: makeTempGraphURL()),
            workflowIndex: WorkflowIndex(),
            memoryStore: UnifiedMemoryStore()
        )

        let scoredSources = scored.map(\.sourceType)
        #expect(scoredSources.contains(.workflow), "workflow source type should be preserved through evaluation")
        #expect(scoredSources.contains(.stableGraph), "stableGraph source type should be preserved through evaluation")
    }

    private func planningState(
        id: String,
        appID: String,
        domain: String?,
        taskPhase: String,
        modalClass: String?
    ) -> PlanningState {
        PlanningState(
            id: PlanningStateID(rawValue: id),
            clusterKey: StateClusterKey(rawValue: id),
            appID: appID,
            domain: domain,
            windowClass: nil,
            taskPhase: taskPhase,
            focusedRole: nil,
            modalClass: modalClass,
            navigationClass: nil,
            controlContext: nil
        )
    }

    private func makeTempGraphURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("graph.sqlite3", isDirectory: false)
    }
}
