import Foundation

/// Canonical runtime-facing planner API.
///
/// `PlanGenerator` is the single entry point that produces ranked plan
/// candidates from three sources (workflow, graph, reasoning) and evaluates
/// them through `PlanEvaluator`. External callers should reach this type
/// only through the planner boundary; direct instantiation from
/// planning files is forbidden by governance tests.
public final class PlanGenerator: @unchecked Sendable {
    private let reasoningEngine: ReasoningEngine
    private let planEvaluator: PlanEvaluator
    private let operatorRegistry: OperatorRegistry
    private let osPlanner: OSPlanner
    private let codePlanner: CodePlanner
    private let mixedTaskPlanner: MixedTaskPlanner


    public init(
        reasoningEngine: ReasoningEngine = ReasoningEngine(),
        planEvaluator: PlanEvaluator,
        operatorRegistry: OperatorRegistry = .shared,
        osPlanner: OSPlanner? = nil,
        codePlanner: CodePlanner? = nil,
        mixedTaskPlanner: MixedTaskPlanner? = nil
    ) {
        self.reasoningEngine = reasoningEngine
        self.planEvaluator = planEvaluator
        self.operatorRegistry = operatorRegistry
        
        let sharedWorkflowIndex = WorkflowIndex()
        let sharedWorkflowRetriever = WorkflowRetriever()
        let sharedWorkflowExecutor = WorkflowExecutor()
        let sharedGraphPlanner = GraphPlanner()
        
        self.osPlanner = osPlanner ?? OSPlanner(
            graphPlanner: sharedGraphPlanner,
            workflowIndex: sharedWorkflowIndex,
            workflowRetriever: sharedWorkflowRetriever,
            workflowExecutor: sharedWorkflowExecutor
        )
        self.codePlanner = codePlanner ?? CodePlanner(
            graphPlanner: sharedGraphPlanner,
            workflowIndex: sharedWorkflowIndex,
            workflowRetriever: sharedWorkflowRetriever,
            workflowExecutor: sharedWorkflowExecutor
        )
        self.mixedTaskPlanner = mixedTaskPlanner ?? MixedTaskPlanner(
            osPlanner: self.osPlanner,
            codePlanner: self.codePlanner
        )
    }


    public func generate(
        state: ReasoningPlanningState,
        taskContext: TaskContext,
        goal: Goal,
        worldState: WorldState,
        graphStore: GraphStore,
        workflowIndex: WorkflowIndex,
memoryStore: UnifiedMemoryStore,
        selectedStrategy: SelectedStrategy
    ) -> [PlanCandidate] {
        var allPlans: [PlanCandidate] = []

        // Source 1: Workflow-backed plans from promoted workflows
        let workflowPlans = workflowBacked(
            goal: goal,
            state: state,
            workflowIndex: workflowIndex
        )
        allPlans.append(contentsOf: workflowPlans)

        // Source 2: Graph-backed plans from stable edges
        let graphPlans = graphBacked(
            state: state,
            worldState: worldState,
            graphStore: graphStore
        )
        allPlans.append(contentsOf: graphPlans)

        // Source 3: Reasoning-generated plans using operator expansion
        let reasoningPlans = reasoningEngine.generatePlans(from: state)
        allPlans.append(contentsOf: reasoningPlans)

        // Source 4: Family-specific planning (OS, Code, Mixed)
        let familyPlans = familyBacked(
            state: state,
            taskContext: taskContext,
            worldState: worldState,
            graphStore: graphStore,
            memoryStore: memoryStore,
            selectedStrategy: selectedStrategy
        )
        allPlans.append(contentsOf: familyPlans)


        // ── Strategy filter: drop plans whose operator families violate the strategy ──
        allPlans = allPlans.filter { $0.isAllowed(by: selectedStrategy) }

        let scored = planEvaluator.evaluate(
            plans: allPlans,
            taskContext: taskContext,
            goal: goal,
            worldState: worldState,
            graphStore: graphStore,
            workflowIndex: workflowIndex,
            memoryStore: memoryStore
        )
        return scored
    }

    public func bestPlan(
        state: ReasoningPlanningState,
        taskContext: TaskContext,
        goal: Goal,
        worldState: WorldState,
        graphStore: GraphStore,
        workflowIndex: WorkflowIndex,
memoryStore: UnifiedMemoryStore,
        minimumScore: Double = 0.6,
        selectedStrategy: SelectedStrategy
    ) -> PlanCandidate? {
        let scored = generate(
            state: state,
            taskContext: taskContext,
            goal: goal,
            worldState: worldState,
            graphStore: graphStore,
            workflowIndex: workflowIndex,
            memoryStore: memoryStore,
            selectedStrategy: selectedStrategy
        )
        return planEvaluator.chooseBestPlan(scored, minimumScore: minimumScore)
    }

    // MARK: - Multi-source plan generation

    private func workflowBacked(
        goal: Goal,
        state: ReasoningPlanningState,
        workflowIndex: WorkflowIndex
    ) -> [PlanCandidate] {
        let matches = workflowIndex.matching(goal: goal)
        let available = operatorRegistry.available(for: state)
        let opsBySkill = Dictionary(
            grouping: available,
            by: { $0.actionContract(for: state, goal: goal)?.skillName ?? "" }
        ).compactMapValues(\.first)
        return matches.compactMap { plan -> PlanCandidate? in
            let ops = plan.steps.compactMap { step -> Operator? in
                opsBySkill[step.actionContract.skillName]
            }
            guard !ops.isEmpty else { return nil }
            var projected = state
            for op in ops { projected = op.effect(projected) }
            return PlanCandidate(
                operators: ops,
                projectedState: projected,
                reasons: ["workflow-backed plan from \(plan.goalPattern)"],
                sourceType: .workflow
            )
        }
    }

    private func graphBacked(
        state: ReasoningPlanningState,
        worldState: WorldState,
        graphStore: GraphStore
    ) -> [PlanCandidate] {
        let stableEdges = graphStore.outgoingStableEdges(from: worldState.planningState.id)
        let available = operatorRegistry.available(for: state)
        let opsByName = Dictionary(uniqueKeysWithValues: available.map { ($0.name, $0) })
        return stableEdges.compactMap { edge -> PlanCandidate? in
            guard let contract = graphStore.actionContract(for: edge.actionContractID) else {
                return nil
            }
            let matchingOp = opsByName.values.first { $0.name == contract.skillName }
                ?? available.first { $0.kind.rawValue == contract.skillName }
            guard let op = matchingOp else { return nil }
            let projected = op.effect(state)
            return PlanCandidate(
                operators: [op],
                projectedState: projected,
                reasons: ["graph-backed plan from stable edge \(edge.actionContractID)"],
                sourceType: .stableGraph
            )
        }
    }

    private func familyBacked(
        state: ReasoningPlanningState,
        taskContext: TaskContext,
        worldState: WorldState,
        graphStore: GraphStore,
        memoryStore: UnifiedMemoryStore,
        selectedStrategy: SelectedStrategy
    ) -> [PlanCandidate] {
        let decision: PlannerDecision? = switch taskContext.agentKind {
        case .os:
            osPlanner.nextStep(
                taskContext: taskContext,
                worldState: worldState,
                graphStore: graphStore,
                memoryStore: memoryStore,
                selectedStrategy: selectedStrategy
            )
        case .code:
            codePlanner.nextStep(
                taskContext: taskContext,
                worldState: worldState,
                graphStore: graphStore,
                memoryStore: memoryStore,
                selectedStrategy: selectedStrategy
            )
        case .mixed:
            mixedTaskPlanner.nextStep(
                taskContext: taskContext,
                worldState: worldState,
                graphStore: graphStore,
                memoryStore: memoryStore,
                selectedStrategy: selectedStrategy
            )
        }

        guard let decision else { return [] }

        let available = operatorRegistry.available(for: state)
        let matchingOp = available.first { $0.kind.rawValue == decision.actionContract.skillName }
        guard let op = matchingOp else { return [] }

        return [
            PlanCandidate(
                operators: [op],
                projectedState: op.effect(state),
                reasons: decision.notes + ["family-backed decision from \(decision.plannerFamily)"],
                sourceType: decision.source.planSourceType
            )
        ]
    }
}

private extension PlannerSource {
    var planSourceType: PlanSourceType {
        switch self {
        case .workflow:
            return .workflow
        case .stableGraph:
            return .stableGraph
        case .candidateGraph:
            return .candidateGraph
        case .exploration:
            return .exploration
        case .reasoning:
            return .reasoning
        case .llm:
            return .llm
        case .recovery:
            return .recovery
        case .strategy:
            return .strategy
        }
    }
}
