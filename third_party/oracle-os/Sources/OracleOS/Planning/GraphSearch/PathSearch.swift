import Foundation

public struct PathSearch: Sendable {
    private struct ScoredPath {
        let stateID: PlanningStateID
        let edges: [EdgeTransition]
        let score: Double
        let visitedStateIDs: Set<String>
    }

    /// Penalty applied each time a path revisits a state already on its own path,
    /// discouraging cycles in favor of novel exploration.
    public static let defaultCyclePenalty: Double = 0.5

    public let maxDepth: Int
    public let beamWidth: Int
    public let cyclePenalty: Double
    private let scorer: PathScorer

    public init(
        maxDepth: Int = 4,
        beamWidth: Int = 5,
        cyclePenalty: Double = PathSearch.defaultCyclePenalty,
        scorer: PathScorer = PathScorer()
    ) {
        self.maxDepth = maxDepth
        self.beamWidth = beamWidth
        self.cyclePenalty = cyclePenalty
        self.scorer = scorer
    }

    public func search(
        from startState: PlanningState,
        goal: Goal,
        graphStore: GraphStore,
        memoryBiasProvider: (EdgeTransition, ActionContract?) -> Double = { _, _ in 0 },
        riskPenaltyProvider: (EdgeTransition, ActionContract?) -> Double = { _, _ in 0 }
    ) -> GraphSearchResult? {
        var exploredEdgeIDs: [String] = []
        var exploredStateIDs: [String] = [startState.id.rawValue]
        var rejectedEdgeIDs: [String] = []
        var cycleDetections: Int = 0
        let initialVisited: Set<String> = [startState.id.rawValue]
        var frontier: [ScoredPath] = [
            ScoredPath(stateID: startState.id, edges: [], score: 0, visitedStateIDs: initialVisited),
        ]
        var bestPath: ScoredPath?

        // Track (stateID, depth) pairs globally to avoid expanding the same state
        // at the same depth across different beam entries.
        var expandedAtDepth: Set<String> = []

        for depth in 0..<maxDepth {
            var nextFrontier: [ScoredPath] = []

            for path in frontier {
                exploredStateIDs.append(path.stateID.rawValue)

                // Deduplicate: skip if this (state, depth) was already expanded.
                let stateDepthKey = "\(path.stateID.rawValue)@\(depth)"
                guard expandedAtDepth.insert(stateDepthKey).inserted else {
                    continue
                }

                if let currentState = graphStore.planningState(for: path.stateID),
                   MainPlanner.goalMatchScore(state: currentState, goal: goal) >= 1 {
                    return GraphSearchResult(
                        edges: path.edges,
                        reachedGoal: true,
                        exploredEdgeIDs: exploredEdgeIDs,
                        diagnostics: GraphSearchDiagnostics(
                            exploredStateIDs: Array(Set(exploredStateIDs)).sorted(),
                            exploredEdgeIDs: exploredEdgeIDs,
                            chosenPathEdgeIDs: path.edges.map(\.edgeID),
                            rejectedEdgeIDs: rejectedEdgeIDs,
                            cycleDetections: cycleDetections
                        )
                    )
                }

                let outgoing = graphStore.outgoingStableEdges(from: path.stateID)
                    .filter { edge in
                        guard let preferredAgentKind = goal.preferredAgentKind else {
                            return true
                        }
                        return edge.agentKind == preferredAgentKind
                    }

                for edge in outgoing {
                    exploredEdgeIDs.append(edge.edgeID)
                    let contract = graphStore.actionContract(for: edge.actionContractID)
                    let memoryBias = memoryBiasProvider(edge, contract)
                    let riskPenalty = riskPenaltyProvider(edge, contract)
                    var edgeScore = scorer.score(
                        edge: edge,
                        actionContract: contract,
                        goal: goal,
                        memoryBias: memoryBias,
                        riskPenalty: riskPenalty
                    )

                    // Apply cycle penalty when the target state is already on this path.
                    let targetID = edge.toPlanningStateID.rawValue
                    if path.visitedStateIDs.contains(targetID) {
                        edgeScore -= cyclePenalty
                        cycleDetections += 1
                    }

                    var updatedVisited = path.visitedStateIDs
                    updatedVisited.insert(targetID)

                    let candidate = ScoredPath(
                        stateID: edge.toPlanningStateID,
                        edges: path.edges + [edge],
                        score: path.score + edgeScore,
                        visitedStateIDs: updatedVisited
                    )
                    nextFrontier.append(candidate)
                    if bestPath.map({ candidate.score > $0.score }) ?? true {
                        bestPath = candidate
                    }
                }
            }

            frontier = nextFrontier
                .sorted { lhs, rhs in
                    if lhs.score == rhs.score {
                        return lhs.edges.count < rhs.edges.count
                    }
                    return lhs.score > rhs.score
                }
                .prefix(beamWidth)
                .map { $0 }

            let keptEdgeIDs = Set(frontier.compactMap { $0.edges.last?.edgeID })
            rejectedEdgeIDs.append(contentsOf: nextFrontier.compactMap { candidate in
                guard let edgeID = candidate.edges.last?.edgeID else {
                    return nil
                }
                return keptEdgeIDs.contains(edgeID) ? nil : edgeID
            })

            if frontier.isEmpty {
                break
            }
        }

        guard let bestPath, !bestPath.edges.isEmpty else {
            return nil
        }

        return GraphSearchResult(
            edges: bestPath.edges,
            reachedGoal: false,
            exploredEdgeIDs: exploredEdgeIDs,
            diagnostics: GraphSearchDiagnostics(
                exploredStateIDs: Array(Set(exploredStateIDs)).sorted(),
                exploredEdgeIDs: exploredEdgeIDs,
                chosenPathEdgeIDs: bestPath.edges.map(\.edgeID),
                rejectedEdgeIDs: rejectedEdgeIDs,
                fallbackReason: "no stable path reached the goal within depth \(maxDepth)",
                cycleDetections: cycleDetections
            )
        )
    }
}
