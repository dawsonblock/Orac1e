import Foundation

public struct Proposal: Sendable {
    public let plans: [PlanCandidate]
    public let selectedPlan: PlanCandidate?
    public let diagnostics: ProposalDiagnostics

    public init(
        plans: [PlanCandidate],
        selectedPlan: PlanCandidate?,
        diagnostics: ProposalDiagnostics
    ) {
        self.plans = plans
        self.selectedPlan = selectedPlan
        self.diagnostics = diagnostics
    }
}

public struct ProposalDiagnostics: Sendable {
    public let llmPlansGenerated: Int
    public let deterministicPlansGenerated: Int
    public let totalEvaluated: Int
    public let selectedSource: PlanSourceType?
    public let llmLatencyMs: Double
    public let notes: [String]

    public init(
        llmPlansGenerated: Int = 0,
        deterministicPlansGenerated: Int = 0,
        totalEvaluated: Int = 0,
        selectedSource: PlanSourceType? = nil,
        llmLatencyMs: Double = 0,
        notes: [String] = []
    ) {
        self.llmPlansGenerated = llmPlansGenerated
        self.deterministicPlansGenerated = deterministicPlansGenerated
        self.totalEvaluated = totalEvaluated
        self.selectedSource = selectedSource
        self.llmLatencyMs = llmLatencyMs
        self.notes = notes
    }
}

public final class ProposalEngine: @unchecked Sendable {
    private let llmClient: LLMClient
    private let reasoningEngine: ReasoningEngine
    private let planEvaluator: PlanEvaluator

    // Stores the latency (in milliseconds) of the most recent LLM planning request.
    private var lastLLMPlanningLatencyMs: Double = 0

    public init(
        llmClient: LLMClient,
        reasoningEngine: ReasoningEngine = ReasoningEngine(),
        planEvaluator: PlanEvaluator
    ) {
        self.llmClient = llmClient
        self.reasoningEngine = reasoningEngine
        self.planEvaluator = planEvaluator
    }

    public func propose(
        state: ReasoningPlanningState,
        taskContext: TaskContext,
        goal: Goal,
        worldState: WorldState,
        graphStore: GraphStore,
        workflowIndex: WorkflowIndex,
memoryStore: UnifiedMemoryStore,
        selectedStrategy: SelectedStrategy
    ) async -> Proposal {
        let deterministicPlans = reasoningEngine.generatePlans(from: state)

        let (llmPlans, llmLatencyMs) = await generateLLMPlans(
            state: state,
            goal: goal,
            operators: deterministicPlans.flatMap(\.operators).map(\.name),
            selectedStrategy: selectedStrategy
        )

        var allPlans = deterministicPlans + llmPlans

        // ── Strategy filter: drop plans outside allowed operator families ──
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

        let best = planEvaluator.chooseBestPlan(scored)

        let selectedSource: PlanSourceType?
        if let best {
            let isLLMPlan = llmPlans.contains { candidate in
                candidate.operators.map(\.kind) == best.operators.map(\.kind)
            }
            selectedSource = isLLMPlan ? .llm : .reasoning
        } else {
            selectedSource = nil
        }

        return Proposal(
            plans: scored,
            selectedPlan: best,
            diagnostics: ProposalDiagnostics(
                llmPlansGenerated: llmPlans.count,
                deterministicPlansGenerated: deterministicPlans.count,
                totalEvaluated: scored.count,
                selectedSource: selectedSource,
                llmLatencyMs: llmLatencyMs ?? 0,
                notes: best == nil ? ["no plan met minimum score threshold"] : []
            )
        )
    }

    private func generateLLMPlans(
        state: ReasoningPlanningState,
        goal: Goal,
        operators: [String],
        selectedStrategy: SelectedStrategy
    ) async -> ([PlanCandidate], Double?) {
        let prompt = buildPlanningPrompt(state: state, goal: goal, operators: operators, selectedStrategy: selectedStrategy)
        let request = LLMRequest(
            prompt: prompt,
            modelTier: .planning,
            maxTokens: 1024,
            temperature: 0.3
        )

        do {
            let response = try await llmClient.complete(request)
            // Preserve the LLM latency so it can be exposed via ProposalDiagnostics.
            self.lastLLMPlanningLatencyMs = response.latencyMs
            let parsed = ReasoningParser.parsePlans(from: response.text)
            let plans = ReasoningParser.toPlanCandidates(
                parsedPlans: parsed,
                state: state
            )
            return (plans, response.latencyMs)
        } catch {
            return ([], nil)
        }
    }

    private func buildPlanningPrompt(
        state: ReasoningPlanningState,
        goal: Goal,
        operators: [String],
        selectedStrategy: SelectedStrategy
    ) -> String {
        var lines: [String] = []
        lines.append("You are controlling a computer operator.")
        lines.append("")

        // ── Strategy context: bound the LLM's reasoning ──
        lines.append("Current strategy: \(selectedStrategy.kind.rawValue)")
        lines.append("Allowed operator families: \(selectedStrategy.allowedOperatorFamilies.map(\.rawValue).joined(separator: ", "))")
        lines.append("Strategy rationale: \(selectedStrategy.rationale)")
        lines.append("IMPORTANT: Only generate plans using operators from the allowed families.")
        lines.append("")

        lines.append("Current state:")
        lines.append("- agent kind: \(state.agentKind.rawValue)")
        lines.append("- active application: \(state.activeApplication ?? "none")")
        lines.append("- target application: \(state.targetApplication ?? "none")")
        lines.append("- repo open: \(state.repoOpen)")
        lines.append("- modal present: \(state.modalPresent)")
        lines.append("- patch applied: \(state.patchApplied)")
        lines.append("- tests observed: \(state.testsObserved)")
        lines.append("")
        lines.append("Goal:")
        lines.append("- \(goal.description)")
        lines.append("")
        lines.append("Available operators:")
        for op in Set(operators).sorted() {
            lines.append("- \(op)")
        }
        lines.append("")
        lines.append("Generate 3 candidate plans.")
        lines.append("Each plan must contain:")
        lines.append("- ordered steps")
        lines.append("- risk level (low, medium, high)")
        lines.append("- confidence (0.0 to 1.0)")
        lines.append("")
        lines.append("Format:")
        lines.append("PLAN 1")
        lines.append("steps:")
        lines.append("- step description")
        lines.append("risk: low")
        lines.append("confidence: 0.75")
        return lines.joined(separator: "\n")
    }
}
