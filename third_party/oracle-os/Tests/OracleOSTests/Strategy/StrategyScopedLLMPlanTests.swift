import Foundation
import Testing
@testable import OracleOS

@Suite("Strategy-Scoped LLM Plan Generation")
struct StrategyScopedLLMPlanTests {

    @Test("PlanGenerator requires non-optional strategy")
    func planGeneratorRequiresStrategy() {
        let engine = ReasoningEngine()
        let evaluator = PlanEvaluator()
        let generator = PlanGenerator(
            reasoningEngine: engine,
            planEvaluator: evaluator
        )

        let state = makeReasoningState()
        let goal = Goal(description: "fix tests", preferredAgentKind: .code)
        let worldState = makeWorldState(app: "Workspace")
        let graphStore = GraphStore()
        let workflowIndex = WorkflowIndex()
        let memoryStore = UnifiedMemoryStore()

        let repoStrategy = SelectedStrategy(
            kind: .repoRepair,
            confidence: 0.8,
            rationale: "repo repair",
            allowedOperatorFamilies: [.repoAnalysis, .patchGeneration, .recovery]
        )

        let plans = generator.generate(
            state: state,
            taskContext: TaskContext.from(goal: goal, workspaceRoot: nil),
            goal: goal,
            worldState: worldState,
            graphStore: graphStore,
            workflowIndex: workflowIndex,
            memoryStore: memoryStore,
            selectedStrategy: repoStrategy
        )

        // All returned plans must be allowed by the strategy
        for plan in plans {
            #expect(plan.isAllowed(by: repoStrategy),
                    "Plan with families \(plan.operatorFamilies) should be allowed by repoRepair")
        }
    }

    @Test("PlanCandidate isAllowed rejects plans outside strategy scope")
    func planCandidateRejectsCrossStrategy() {
        let state = makeReasoningState()

        let repoStrategy = SelectedStrategy(
            kind: .repoRepair,
            confidence: 0.8,
            rationale: "repair",
            allowedOperatorFamilies: [.repoAnalysis, .patchGeneration]
        )

        // Browser plan → should NOT be allowed under repoRepair
        let browserPlan = PlanCandidate(
            operators: [Operator(kind: .navigateBrowser), Operator(kind: .clickTarget)],
            projectedState: state
        )
        #expect(!browserPlan.isAllowed(by: repoStrategy))

        // Repo plan → should be allowed
        let repoPlan = PlanCandidate(
            operators: [Operator(kind: .runTests), Operator(kind: .applyPatch)],
            projectedState: state
        )
        #expect(repoPlan.isAllowed(by: repoStrategy))
    }

    @Test("ProposalEngine requires non-optional strategy")
    func proposalEngineRequiresStrategy() async {
        let llmClient = LLMClient()
        let evaluator = PlanEvaluator()
        let engine = ProposalEngine(
            llmClient: llmClient,
            planEvaluator: evaluator
        )

        let state = makeReasoningState()
        let goal = Goal(description: "fix tests", preferredAgentKind: .code)
        let worldState = makeWorldState(app: "Workspace")

        let strategy = SelectedStrategy(
            kind: .repoRepair,
            confidence: 0.8,
            rationale: "repo repair",
            allowedOperatorFamilies: [.repoAnalysis, .patchGeneration, .recovery]
        )

        let proposal = await engine.propose(
            state: state,
            taskContext: TaskContext.from(goal: goal, workspaceRoot: nil),
            goal: goal,
            worldState: worldState,
            graphStore: GraphStore(),
            workflowIndex: WorkflowIndex(),
            memoryStore: UnifiedMemoryStore(),
            selectedStrategy: strategy
        )

        // All returned plans must respect the strategy
        for plan in proposal.plans {
            #expect(plan.isAllowed(by: strategy))
        }
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
}
