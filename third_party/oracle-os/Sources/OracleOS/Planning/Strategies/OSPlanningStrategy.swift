import Foundation

public final class OSPlanner: @unchecked Sendable {
    private let graphPlanner: GraphPlanner
    private let explorationPolicy: ExplorationPolicy
    private let workflowIndex: WorkflowIndex
    private let workflowRetriever: WorkflowRetriever
    private let workflowExecutor: WorkflowExecutor
    private let promptEngine: PromptEngine

    public init(
        graphPlanner: GraphPlanner = GraphPlanner(),
        explorationPolicy: ExplorationPolicy = ExplorationPolicy(),
        workflowIndex: WorkflowIndex = WorkflowIndex(),
        workflowRetriever: WorkflowRetriever = WorkflowRetriever(),
        workflowExecutor: WorkflowExecutor = WorkflowExecutor(),
        promptEngine: PromptEngine = PromptEngine()
    ) {
        self.graphPlanner = graphPlanner
        self.explorationPolicy = explorationPolicy
        self.workflowIndex = workflowIndex
        self.workflowRetriever = workflowRetriever
        self.workflowExecutor = workflowExecutor
        self.promptEngine = promptEngine
    }

    public func nextStep(
        taskContext: TaskContext,
        worldState: WorldState,
        graphStore: GraphStore,
        memoryStore: UnifiedMemoryStore,
        selectedStrategy: SelectedStrategy
    ) -> PlannerDecision? {
        if let workflowMatch = workflowRetriever.retrieve(
            goal: taskContext.goal,
            taskContext: taskContext,
            worldState: worldState,
            workflowIndex: workflowIndex,
            memoryStore: memoryStore,
            selectedStrategy: selectedStrategy
        ) {
            let decision = workflowExecutor.nextDecision(
                match: workflowMatch,
                plannerFamily: .os,
                sourceNotes: ["workflow-first planner hit"]
            )
            return decision.with(promptDiagnostics: promptEngine.workflowSelection(
                goal: taskContext.goal,
                taskContext: taskContext,
                worldState: worldState,
                match: workflowMatch
            ).diagnostics)
        }

        let graphGoal = Goal(
            description: taskContext.goal.description,
            targetApp: taskContext.goal.targetApp,
            targetDomain: taskContext.goal.targetDomain,
            targetTaskPhase: taskContext.goal.targetTaskPhase,
            workspaceRoot: taskContext.goal.workspaceRoot,
            preferredAgentKind: .os
        )
        if let searchResult = graphPlanner.search(
            from: worldState.planningState,
            goal: graphGoal,
            graphStore: graphStore,
            memoryStore: memoryStore,
            worldState: worldState
        ),
           let currentEdge = searchResult.edges.first,
           let contract = graphStore.actionContract(for: currentEdge.actionContractID)
        {
            let decision = PlannerDecision(
                agentKind: .os,
                plannerFamily: .os,
                stepPhase: .operatingSystem,
                actionContract: contract,
                source: .stableGraph,
                pathEdgeIDs: searchResult.edges.map(\.edgeID),
                currentEdgeID: currentEdge.edgeID,
                fallbackReason: "workflow retrieval did not yield a reusable plan",
                graphSearchDiagnostics: searchResult.diagnostics,
                semanticQuery: semanticQuery(for: contract, worldState: worldState),
                notes: graphNotes(
                    prefix: searchResult.reachedGoal ? "stable graph path reaches goal" : "stable graph path improves goal fit",
                    diagnostics: searchResult.diagnostics
                )
            )
            return decision.with(promptDiagnostics: promptDiagnostics(
                goal: taskContext.goal,
                worldState: worldState,
                decision: decision
            ))
        }

        if let candidateSelection = graphPlanner.bestCandidateEdge(
            from: worldState.planningState,
            goal: graphGoal,
            graphStore: graphStore,
            memoryStore: memoryStore,
            worldState: worldState
        ),
           let contract = candidateSelection.actionContract
        {
            let decision = PlannerDecision(
                agentKind: .os,
                plannerFamily: .os,
                stepPhase: .operatingSystem,
                actionContract: contract,
                source: .candidateGraph,
                pathEdgeIDs: [candidateSelection.edge.edgeID],
                currentEdgeID: candidateSelection.edge.edgeID,
                fallbackReason: "workflow retrieval and stable graph path reuse were unavailable",
                graphSearchDiagnostics: candidateSelection.diagnostics,
                semanticQuery: semanticQuery(for: contract, worldState: worldState),
                notes: graphNotes(
                    prefix: "candidate graph edge reuse",
                    diagnostics: candidateSelection.diagnostics
                ) + ["candidate score \(String(format: "%.2f", candidateSelection.score))"]
            )
            return decision.with(promptDiagnostics: promptDiagnostics(
                goal: taskContext.goal,
                worldState: worldState,
                decision: decision
            ))
        }

        guard let fallback = explorationPolicy.choose(goal: taskContext.goal, worldState: worldState) else {
            return nil
        }
        let decision = PlannerDecision(
            agentKind: .os,
            skillName: fallback.skillName,
            plannerFamily: .os,
            stepPhase: .operatingSystem,
            actionContract: fallback.actionContract,
            source: fallback.source,
            pathEdgeIDs: fallback.pathEdgeIDs,
            currentEdgeID: fallback.currentEdgeID,
            fallbackReason: "workflow retrieval, stable graph path reuse, and candidate graph reuse were unavailable",
            semanticQuery: fallback.semanticQuery,
            notes: fallback.notes + ["workflow and graph reuse unavailable"],
            recoveryTagged: fallback.recoveryTagged,
            recoveryStrategy: fallback.recoveryStrategy,
            recoverySource: fallback.recoverySource
        )
        return decision.with(promptDiagnostics: promptDiagnostics(
            goal: taskContext.goal,
            worldState: worldState,
            decision: decision
        ))
    }

    private func semanticQuery(
        for contract: ActionContract,
        worldState: WorldState
    ) -> ElementQuery? {
        guard contract.skillName == "click" || contract.skillName == "type" || contract.skillName == "fill_form" || contract.skillName == "read_file" else {
            return nil
        }

        return ElementQuery(
            text: contract.targetLabel,
            role: contract.targetRole,
            editable: contract.skillName == "type" || contract.skillName == "fill_form",
            clickable: contract.skillName == "click" || contract.skillName == "read_file",
            visibleOnly: true,
            app: worldState.observation.app
        )
    }

    private func graphNotes(prefix: String, diagnostics: GraphSearchDiagnostics) -> [String] {
        var notes = [prefix, "explored \(diagnostics.exploredEdgeIDs.count) graph edges"]
        if !diagnostics.rejectedEdgeIDs.isEmpty {
            notes.append("rejected \(diagnostics.rejectedEdgeIDs.count) alternatives")
        }
        if let fallbackReason = diagnostics.fallbackReason {
            notes.append(fallbackReason)
        }
        return notes
    }

    private func promptDiagnostics(
        goal: Goal,
        worldState: WorldState,
        decision: PlannerDecision
    ) -> PromptDiagnostics {
        promptEngine.osAction(
            goal: goal,
            worldState: worldState,
            actionContract: decision.actionContract,
            semanticQuery: decision.semanticQuery,
            source: decision.source,
            fallbackReason: decision.fallbackReason,
            notes: decision.notes
        ).diagnostics
    }
}
