import Foundation

/// Expands candidate paths from the current task-graph node.
///
/// ``LedgerNavigator`` is the component the planner calls to obtain ranked
/// future paths. It combines existing edges with freshly generated
/// candidate edges, then expands them to a bounded depth.
public struct LedgerNavigator: Sendable {
    public let maxDepth: Int
    public let maxBranching: Int
    public let beamWidth: Int

    public init(maxDepth: Int = 3, maxBranching: Int = 5, beamWidth: Int = 4) {
        precondition(
            maxDepth >= 0 && maxBranching >= 0 && beamWidth >= 0,
            "LedgerNavigator parameters must be non-negative."
        )
        self.maxDepth = maxDepth
        self.maxBranching = maxBranching
        self.beamWidth = beamWidth
    }

    /// A single scored path through the task graph.
    public struct ScoredPath: Sendable {
        public let edges: [TaskRecordEdge]
        public let nodes: [TaskRecord]
        public let cumulativeScore: Double
        public let terminalState: AbstractTaskState?
    }

    /// Expand outgoing edges from the current node and return scored paths
    /// up to ``maxDepth`` hops.
    public func expand(
        from nodeID: String,
        in graph: TaskLedger,
        scorer: LedgerScorer,
        goal: Goal? = nil,
        allowedFamilies: [OperatorFamily]
    ) -> [ScoredPath] {
        guard let startNode = graph.node(for: nodeID) else { return [] }

        var results: [ScoredPath] = []
        var visited: Set<String> = [nodeID]

        expandRecursive(
            currentNode: startNode,
            currentEdges: [],
            currentNodes: [startNode],
            cumulativeScore: 0,
            depth: 0,
            visited: &visited,
            graph: graph,
            scorer: scorer,
            goal: goal,
            allowedFamilies: allowedFamilies,
            results: &results
        )

        return results.sorted { $0.cumulativeScore > $1.cumulativeScore }
            .prefix(beamWidth * maxDepth)
            .map { $0 }
    }

    /// Return the best single next edge from the current node.
    public func bestNextEdge(
        from nodeID: String,
        in graph: TaskLedger,
        scorer: LedgerScorer,
        goal: Goal? = nil,
        allowedFamilies: [OperatorFamily]
    ) -> TaskRecordEdge? {
        let paths = expand(from: nodeID, in: graph, scorer: scorer, goal: goal, allowedFamilies: allowedFamilies)
        return paths.first?.edges.first
    }

    // MARK: - Private

    private func expandRecursive(
        currentNode: TaskRecord,
        currentEdges: [TaskRecordEdge],
        currentNodes: [TaskRecord],
        cumulativeScore: Double,
        depth: Int,
        visited: inout Set<String>,
        graph: TaskLedger,
        scorer: LedgerScorer,
        goal: Goal?,
        allowedFamilies: [OperatorFamily],
        results: inout [ScoredPath]
    ) {
        // Record the path ending here when depth > 0
        if !currentEdges.isEmpty {
            results.append(ScoredPath(
                edges: currentEdges,
                nodes: currentNodes,
                cumulativeScore: cumulativeScore,
                terminalState: currentNode.abstractState
            ))
        }

        guard depth < maxDepth else { return }

        var outgoing = graph.viableEdges(from: currentNode.id)

        // ── Strategy filter: only expand edges whose operator family is allowed ──
        outgoing = outgoing.filter { edge in
            let family = Self.operatorFamilyForAction(edge.action)
            return allowedFamilies.contains(family)
        }

        let sorted = outgoing
            .sorted { scorer.scoreEdge($0) > scorer.scoreEdge($1) }
            .prefix(maxBranching)

        for edge in sorted {
            let toID = edge.toNodeID
            guard !visited.contains(toID) else { continue }
            guard let toNode = graph.node(for: toID) else { continue }

            let edgeScore = scorer.scoreEdge(edge, goalState: goal.flatMap {
                LedgerScorer.goalAbstractState(from: $0)
            }, targetState: toNode.abstractState)

            visited.insert(toID)
            expandRecursive(
                currentNode: toNode,
                currentEdges: currentEdges + [edge],
                currentNodes: currentNodes + [toNode],
                cumulativeScore: cumulativeScore + edgeScore,
                depth: depth + 1,
                visited: &visited,
                graph: graph,
                scorer: scorer,
                goal: goal,
                allowedFamilies: allowedFamilies,
                results: &results
            )
            visited.remove(toID)
        }
    }

    /// Infer the operator family for a graph edge action name.
    public static func operatorFamilyForAction(_ action: String) -> OperatorFamily {
        let lowered = action.lowercased()
        if lowered.contains("test") || lowered.contains("build") || lowered.contains("compile") {
            return .repoAnalysis
        }
        if lowered.contains("patch") || lowered.contains("revert") || lowered.contains("rollback") {
            return .patchGeneration
        }
        if lowered.contains("experiment") {
            return .patchExperiment
        }
        if lowered.contains("browser") || lowered.contains("navigate") || lowered.contains("click") {
            return .browserTargeted
        }
        if lowered.contains("dismiss") || lowered.contains("retry") || lowered.contains("recovery") {
            return .recovery
        }
        if lowered.contains("open") || lowered.contains("focus") || lowered.contains("restart") {
            return .hostTargeted
        }
        if lowered.contains("permission") || lowered.contains("approve") {
            return .permissionHandling
        }
        if lowered.contains("workflow") {
            return .workflow
        }
        return .graphEdge
    }
}
