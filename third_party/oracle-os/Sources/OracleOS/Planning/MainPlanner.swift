import Foundation

// Planner chooses execution structure only: workflow, graph path, graph edge,
// or bounded exploration. It must not resolve exact UI targets, mutate files,
// execute commands, or inline recovery mechanics.
//
// The planner navigates the live TaskLedger as its primary control substrate.
// Each planning cycle:
//   1. Updates the current task-graph node from world state
//   2. Expands candidate edges from the current node
//   3. Evaluates future paths via LedgerNavigator
//   4. Selects the best edge
// The task graph is the canonical representation of task position — not
// a post-hoc log.
public final class MainPlanner: @unchecked Sendable {
    private var currentGoal: Goal?
    public let workflowIndex: WorkflowIndex
    private let workflowRetriever: WorkflowRetriever
    private let osPlanner: OSPlanner
    private let codePlanner: CodePlanner
    private let mixedTaskPlanner: MixedTaskPlanner
    private let reasoningEngine: ReasoningEngine
    private let planEvaluator: PlanEvaluator
    private let promptEngine: PromptEngine
    private let reasoningThreshold: Double
    public let taskGraphStore: TaskLedgerStore
    private let graphNavigator: LedgerNavigator
    private let graphScorer: LedgerScorer
    private let planGenerator: PlanGenerator

    public init(
        workflowIndex: WorkflowIndex? = nil,
        osPlanner: OSPlanner? = nil,
        codePlanner: CodePlanner? = nil,
        mixedTaskPlanner: MixedTaskPlanner? = nil,
        reasoningEngine: ReasoningEngine? = nil,
        planEvaluator: PlanEvaluator? = nil,
        promptEngine: PromptEngine = PromptEngine(),
        reasoningThreshold: Double = 0.6,
        taskGraphStore: TaskLedgerStore? = nil
    ) {
        let resolvedWorkflowIndex = workflowIndex ?? WorkflowIndex()
        let sharedWorkflowRetriever = WorkflowRetriever()
        let sharedPlanEvaluator = planEvaluator ?? PlanEvaluator(workflowRetriever: sharedWorkflowRetriever)
        let resolvedOSPlanner = osPlanner ?? OSPlanner(
            workflowIndex: resolvedWorkflowIndex,
            workflowRetriever: sharedWorkflowRetriever,
            promptEngine: promptEngine
        )
        let resolvedCodePlanner = codePlanner ?? CodePlanner(
            workflowIndex: resolvedWorkflowIndex,
            workflowRetriever: sharedWorkflowRetriever,
            promptEngine: promptEngine
        )
        let resolvedMixedTaskPlanner = mixedTaskPlanner
            ?? MixedTaskPlanner(osPlanner: resolvedOSPlanner, codePlanner: resolvedCodePlanner)
        
        self.planGenerator = PlanGenerator(
            reasoningEngine: reasoningEngine ?? ReasoningEngine(),
            planEvaluator: sharedPlanEvaluator,
            osPlanner: resolvedOSPlanner,
            codePlanner: resolvedCodePlanner,
            mixedTaskPlanner: resolvedMixedTaskPlanner
        )
        self.workflowIndex = resolvedWorkflowIndex
        self.workflowRetriever = sharedWorkflowRetriever
        self.osPlanner = resolvedOSPlanner
        self.codePlanner = resolvedCodePlanner
        self.mixedTaskPlanner = resolvedMixedTaskPlanner
        self.reasoningEngine = reasoningEngine ?? ReasoningEngine()
        self.planEvaluator = sharedPlanEvaluator
        self.promptEngine = promptEngine
        self.reasoningThreshold = reasoningThreshold
        self.taskGraphStore = taskGraphStore ?? TaskLedgerStore()
        self.graphNavigator = LedgerNavigator()
        self.graphScorer = LedgerScorer()
    }

    public func setGoal(_ goal: Goal) {
        currentGoal = goal
    }

    public func interpretGoal(_ description: String) -> Goal {
        Goal.interpret(description)
    }

    public func goalReached(state: PlanningState) -> Bool {
        guard let currentGoal else { return false }
        return currentGoal.matchScore(state: state) >= 1
    }

    public func nextStep(
        worldState: WorldState,
        graphStore: GraphStore,
        memoryStore: UnifiedMemoryStore = UnifiedMemoryStore(),
        selectedStrategy: SelectedStrategy
    ) -> PlannerDecision? {
        guard let currentGoal else { return nil }

        let workspaceRoot = currentGoal.workspaceRoot.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let taskContext = TaskContext.from(goal: currentGoal, workspaceRoot: workspaceRoot)

        // ── Task-graph substrate: update the current node from world state ──
        // The graph is the canonical representation of task position.
        let currentTaskRecord = taskGraphStore.updateCurrentNode(
            worldState: worldState
        )

        // ── Memory Influence ──
        let _ = MemoryRouter(memoryStore: memoryStore).influence(
            for: MemoryQueryContext(taskContext: taskContext, worldState: worldState)
        )

        // ── Task-graph substrate: try graph-navigated decision first ──
        let taskGraphDecision = taskGraphNavigatedDecision(
            taskNode: currentTaskRecord,
            taskContext: taskContext,
            worldState: worldState,
            graphStore: graphStore,
            memoryStore: memoryStore,
            selectedStrategy: selectedStrategy
        )

        // ── Family decision ──
        let familyDecision = familyPlannerDecision(
            taskContext: taskContext,
            worldState: worldState,
            graphStore: graphStore,
            memoryStore: memoryStore,
            selectedStrategy: selectedStrategy
        )

        // ── Reasoning decision ──
        let reasoning = reasoningDecision(
            taskContext: taskContext,
            worldState: worldState,
            graphStore: graphStore,
            memoryStore: memoryStore,
            fallbackDecision: familyDecision,
            selectedStrategy: selectedStrategy
        )

        // ── Plan Selection ──
        let decision = PlanSelection.selectBest(
            familyDecision: familyDecision,
            reasoningDecision: reasoning,
            taskGraphDecision: taskGraphDecision,
            taskContext: taskContext,
            worldState: worldState,
            memoryStore: memoryStore
        )

        // ── Safety net: strategy check ──
        if let decision {
            let skillName = decision.actionContract.skillName
            let family = operatorFamilyForSkill(skillName)
            if !selectedStrategy.allows(family) {
                return nil
            }
        }

        return decision
    }

    private func familyPlannerDecision(
        taskContext: TaskContext,
        worldState: WorldState,
        graphStore: GraphStore,
        memoryStore: UnifiedMemoryStore,
        selectedStrategy: SelectedStrategy
    ) -> PlannerDecision? {
        switch taskContext.agentKind {
        case .os:
            return osPlanner.nextStep(
                taskContext: taskContext,
                worldState: worldState,
                graphStore: graphStore,
                memoryStore: memoryStore,
                selectedStrategy: selectedStrategy
            )
        case .code:
            return codePlanner.nextStep(
                taskContext: taskContext,
                worldState: worldState,
                graphStore: graphStore,
                memoryStore: memoryStore,
                selectedStrategy: selectedStrategy
            )
        case .mixed:
            return mixedTaskPlanner.nextStep(
                taskContext: taskContext,
                worldState: worldState,
                graphStore: graphStore,
                memoryStore: memoryStore,
                selectedStrategy: selectedStrategy
            )
        }
    }

    private func reasoningDecision(
        taskContext: TaskContext,
        worldState: WorldState,
        graphStore: GraphStore,
        memoryStore: UnifiedMemoryStore,
        fallbackDecision: PlannerDecision?,
        selectedStrategy: SelectedStrategy
    ) -> PlannerDecision? {
        let memoryInfluence = MemoryRouter(memoryStore: memoryStore).influence(
            for: MemoryQueryContext(
                taskContext: taskContext,
                worldState: worldState,
                errorSignature: currentGoal?.description
            )
        )
        let reasoningState = ReasoningPlanningState(
            taskContext: taskContext,
            worldState: worldState,
            memoryInfluence: memoryInfluence
        )
        
        let bestCandidate = planGenerator.bestPlan(
            state: reasoningState,
            taskContext: taskContext,
            goal: currentGoal!,
            worldState: worldState,
            graphStore: graphStore,
            workflowIndex: workflowIndex,
            memoryStore: memoryStore,
            minimumScore: reasoningThreshold,
            selectedStrategy: selectedStrategy
        )

        guard let selectedPlan = bestCandidate,
              let selectedOperator = selectedPlan.operators.first,
              let actionContract = selectedOperator.actionContract(for: reasoningState, goal: currentGoal!)
        else {
            return nil
        }

        if selectedPlan.sourceType == .workflow,
           let fallbackDecision,
           fallbackDecision.source == .workflow {
            return fallbackDecision
        }
        if selectedPlan.sourceType == .stableGraph,
           let fallbackDecision,
           fallbackDecision.source == .stableGraph {
            return fallbackDecision
        }

        let fallbackReason = fallbackDecision?.fallbackReason
            ?? "family planner had no viable workflow or graph-backed step"

        let selectedOperatorNames = selectedPlan.operators.map(\.name)
        let candidateSummaries = [
            ScoredPlanSummary(
                operatorNames: selectedOperatorNames,
                score: selectedPlan.score,
                reasons: selectedPlan.reasons,
                simulatedSuccessProbability: selectedPlan.simulatedOutcome?.successProbability,
                simulatedRiskScore: selectedPlan.simulatedOutcome?.riskScore,
                simulatedFailureMode: selectedPlan.simulatedOutcome?.likelyFailureMode
            ),
        ]
        let planDiagnostics = PlanDiagnostics(
            selectedOperatorNames: selectedOperatorNames,
            candidatePlans: candidateSummaries,
            fallbackReason: fallbackReason
        )
        let promptDiagnostics = promptEngine.planning(
            goal: currentGoal!,
            taskContext: taskContext,
            worldState: worldState,
            selectedOperators: selectedOperatorNames,
            candidatePlans: candidateSummaries,
            fallbackReason: fallbackReason,
            projectMemoryRefs: memoryInfluence.projectMemoryRefs,
            notes: ["reasoning-selected plan"] + selectedPlan.reasons
        ).diagnostics

        return PlannerDecision(
            agentKind: selectedOperator.agentKind,
            plannerFamily: plannerFamily(for: taskContext.agentKind),
            stepPhase: selectedOperator.stepPhase,
            actionContract: actionContract,
            source: selectedPlan.sourceType.plannerSource,
            fallbackReason: fallbackReason,
            semanticQuery: selectedOperator.semanticQuery(for: reasoningState, goal: currentGoal!),
            projectMemoryRefs: memoryInfluence.projectMemoryRefs,
            notes: ["reasoning-selected plan"] + selectedPlan.reasons,
            planDiagnostics: planDiagnostics,
            promptDiagnostics: promptDiagnostics
        )
    }

    private func taskGraphNavigatedDecision(
        taskNode: TaskRecord,
        taskContext: TaskContext,
        worldState: WorldState,
        graphStore: GraphStore,
        memoryStore: UnifiedMemoryStore,
        selectedStrategy: SelectedStrategy
    ) -> PlannerDecision? {
        let graph = taskGraphStore.graph
        let nodeID = taskNode.id
        var outgoing = graph.viableEdges(from: nodeID)

        // ── Strategy filter ──
        outgoing = outgoing.filter { edge in
            let family = operatorFamilyForSkill(edge.action)
            return selectedStrategy.allows(family)
        }

        guard !outgoing.isEmpty else { return nil }

        let memoryInfluence = MemoryRouter(memoryStore: memoryStore).influence(
            for: MemoryQueryContext(taskContext: taskContext, worldState: worldState)
        )
        let memoryBias = MemoryScorer.planBias(influence: memoryInfluence)

        let paths = graphNavigator.expand(
            from: nodeID,
            in: graph,
            scorer: graphScorer,
            goal: currentGoal,
            allowedFamilies: selectedStrategy.allowedOperatorFamilies
        )

        guard let bestPath = paths.first,
              let bestEdge = bestPath.edges.first,
              let contractID = bestEdge.actionContractID else {
            return nil
        }

        let actionContract = graphStore.actionContract(for: contractID)
        guard let actionContract else { return nil }

        let goalState = currentGoal.flatMap { LedgerScorer.goalAbstractState(from: $0) }
        let targetNode = graph.node(for: bestEdge.toNodeID)
        let breakdown = graphScorer.scoreEdgeWithBreakdown(
            bestEdge,
            goalState: goalState,
            targetState: targetNode?.abstractState,
            memoryBias: memoryBias
        )

        return PlannerDecision(
            agentKind: actionContract.agentKind,
            plannerFamily: plannerFamily(for: taskContext.agentKind),
            stepPhase: stepPhase(for: actionContract.agentKind),
            actionContract: actionContract,
            source: .stableGraph,
            fallbackReason: "task-graph path expansion selected edge",
            notes: [
                "task-graph navigated decision",
                "path depth: \(bestPath.edges.count)",
                "path score: \(String(format: "%.3f", bestPath.cumulativeScore))",
                "terminal state: \(bestPath.terminalState?.rawValue ?? "unknown")",
                "memory_bias_contribution: \(String(format: "%.3f", breakdown.memoryBias))",
                "candidate_paths: \(paths.count)",
            ]
        )
    }

    private func stepPhase(for agentKind: AgentKind) -> TaskStepPhase {
        switch agentKind {
        case .os:
            return .operatingSystem
        case .code:
            return .engineering
        case .mixed:
            return .operatingSystem
        }
    }

    private func plannerFamily(for agentKind: AgentKind) -> PlannerFamily {
        switch agentKind {
        case .os:
            return .os
        case .code:
            return .code
        case .mixed:
            return .mixed
        }
    }

    public func nextAction(
        worldState: WorldState,
        graphStore: GraphStore,
        selectedStrategy: SelectedStrategy
    ) -> ActionContract? {
        nextStep(worldState: worldState, graphStore: graphStore, selectedStrategy: selectedStrategy)?.actionContract
    }

    public func plan(goal: String) -> Plan {
        let interpretedGoal = interpretGoal(goal)
        setGoal(interpretedGoal)
        return Plan(goal: goal, steps: ["graph-aware"])
    }

    public static func goalMatchScore(state: PlanningState, goal: Goal) -> Double {
        var matched = 0.0
        var possible = 0.0

        if let targetApp = goal.targetApp {
            possible += 1
            if state.appID == targetApp { matched += 1 }
        }
        if let targetDomain = goal.targetDomain {
            possible += 1
            if state.domain == targetDomain { matched += 1 }
        }
        if let targetTaskPhase = goal.targetTaskPhase {
            possible += 1
            if state.taskPhase == targetTaskPhase { matched += 1 }
        }

        guard possible > 0 else { return 0 }
        return matched / possible
    }

    private func operatorFamilyForSkill(_ skillName: String) -> OperatorFamily {
        LedgerNavigator.operatorFamilyForAction(skillName)
    }
}

private extension PlanSourceType {
    var plannerSource: PlannerSource {
        switch self {
        case .workflow: return .workflow
        case .stableGraph: return .stableGraph
        case .reasoning: return .reasoning
        case .candidateGraph: return .candidateGraph
        case .exploration: return .exploration
        case .llm: return .llm
        case .recovery: return .recovery
        case .strategy: return .strategy
        }
    }
}
