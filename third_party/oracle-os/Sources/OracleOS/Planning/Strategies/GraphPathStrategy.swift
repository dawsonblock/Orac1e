import Foundation

public struct GraphSearchResult: Sendable {
    public let edges: [EdgeTransition]
    public let reachedGoal: Bool
    public let exploredEdgeIDs: [String]
    public let diagnostics: GraphSearchDiagnostics

    public init(
        edges: [EdgeTransition],
        reachedGoal: Bool,
        exploredEdgeIDs: [String],
        diagnostics: GraphSearchDiagnostics
    ) {
        self.edges = edges
        self.reachedGoal = reachedGoal
        self.exploredEdgeIDs = exploredEdgeIDs
        self.diagnostics = diagnostics
    }
}

public final class GraphPlanner: @unchecked Sendable {
    public let maxDepth: Int
    public let beamWidth: Int
    private let pathSearch: PathSearch

    public init(maxDepth: Int = 4, beamWidth: Int = 5) {
        self.maxDepth = maxDepth
        self.beamWidth = beamWidth
        self.pathSearch = PathSearch(maxDepth: maxDepth, beamWidth: beamWidth)
    }

    public func search(
        from startState: PlanningState,
        goal: Goal,
        graphStore: GraphStore,
memoryStore: UnifiedMemoryStore? = nil,
        worldState: WorldState? = nil,
        riskPenalty: Double = 0
    ) -> GraphSearchResult? {
        pathSearch.search(
            from: startState,
            goal: goal,
            graphStore: graphStore
        ) { edge, actionContract in
            let router = memoryStore.map { MemoryRouter(memoryStore: $0) }
            if let commandCategory = edge.commandCategory,
               let workspaceRoot = worldState?.repositorySnapshot?.workspaceRoot,
               let router
            {
                return router.commandBias(
                    category: commandCategory,
                    workspaceRoot: workspaceRoot,
                    repositorySnapshot: worldState?.repositorySnapshot
                )
            }

            guard let router else {
                return 0
            }
            return router.rankingBias(
                label: actionContract?.targetLabel,
                app: worldState?.observation.app,
                goalDescription: goal.description,
                repositorySnapshot: worldState?.repositorySnapshot,
                planningState: worldState?.planningState
            )
        } riskPenaltyProvider: { _, _ in
            riskPenalty
        }
    }

    public func bestCandidateEdge(
        from startState: PlanningState,
        goal: Goal,
        graphStore: GraphStore,
memoryStore: UnifiedMemoryStore? = nil,
        worldState: WorldState? = nil,
        riskPenalty: Double = 0
    ) -> GraphEdgeSelection? {
        let candidateEdges = graphStore.outgoingCandidateEdges(from: startState.id)
            .filter { edge in
                guard let preferredAgentKind = goal.preferredAgentKind else {
                    return true
                }
                return edge.agentKind == preferredAgentKind
            }

        guard !candidateEdges.isEmpty else {
            return nil
        }

        let scored = candidateEdges.map { edge -> GraphEdgeSelection in
            let actionContract = graphStore.actionContract(for: edge.actionContractID)
            let router = memoryStore.map { MemoryRouter(memoryStore: $0) }
            let memoryBias: Double
            if let commandCategory = edge.commandCategory,
               let workspaceRoot = worldState?.repositorySnapshot?.workspaceRoot,
               let router
            {
                memoryBias = router.commandBias(
                    category: commandCategory,
                    workspaceRoot: workspaceRoot,
                    repositorySnapshot: worldState?.repositorySnapshot
                )
            } else if let router {
                memoryBias = router.rankingBias(
                    label: actionContract?.targetLabel,
                    app: worldState?.observation.app,
                    goalDescription: goal.description,
                    repositorySnapshot: worldState?.repositorySnapshot,
                    planningState: worldState?.planningState
                )
            } else {
                memoryBias = 0
            }

            return GraphEdgeSelection(
                edge: edge,
                actionContract: actionContract,
                source: .candidateGraph,
                score: PathScorer().score(
                edge: edge,
                actionContract: actionContract,
                goal: goal,
                memoryBias: memoryBias,
                riskPenalty: riskPenalty
            ),
                diagnostics: GraphSearchDiagnostics(
                    exploredStateIDs: [startState.id.rawValue],
                    exploredEdgeIDs: candidateEdges.map(\.edgeID),
                    chosenPathEdgeIDs: [edge.edgeID]
                )
            )
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.edge.cost < rhs.edge.cost
            }
            return lhs.score > rhs.score
        }

        guard let best = scored.first else {
            return nil
        }

        let rejected = scored.dropFirst().map(\.edge.edgeID)
        return GraphEdgeSelection(
            edge: best.edge,
            actionContract: best.actionContract,
            source: best.source,
            score: best.score,
            diagnostics: GraphSearchDiagnostics(
                exploredStateIDs: best.diagnostics.exploredStateIDs,
                exploredEdgeIDs: best.diagnostics.exploredEdgeIDs,
                chosenPathEdgeIDs: best.diagnostics.chosenPathEdgeIDs,
                rejectedEdgeIDs: rejected
            )
        )
    }
}
