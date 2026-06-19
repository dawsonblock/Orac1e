import Foundation

/// Bounded, in-memory storage for the live task graph.
///
/// ``TaskLedgerStore`` wraps a ``TaskLedger`` with persistence-ready
/// serialisation and enforces growth bounds. It is the single owner of
/// the graph data for a given task session.
public final class TaskLedgerStore: @unchecked Sendable {
    public let graph: TaskLedger
    public let stateAbstractor: StateAbstractor

    public init(
        maxNodesPerTask: Int = 200,
        maxEdgesPerNode: Int = 10
    ) {
        self.graph = TaskLedger(
            maxNodesPerTask: maxNodesPerTask,
            maxEdgesPerNode: maxEdgesPerNode
        )
        self.stateAbstractor = StateAbstractor()
    }

    // MARK: - High-Level Operations

    /// Initialise (or update) the current graph position from a world state.
    @discardableResult
    public func updateCurrentNode(worldState: WorldState, createdByAction: String? = nil) -> TaskRecord {
        let node = stateAbstractor.resolveNode(
            worldState: worldState,
            taskGraph: graph,
            createdByAction: createdByAction
        )
        graph.setCurrent(node.id)
        return node
    }

    /// Add a candidate edge from the current node to a projected future node.
    @discardableResult
    public func addCandidateEdge(
        action: String,
        actionContractID: String? = nil,
        toAbstractState: AbstractTaskState,
        toPlanningStateID: PlanningStateID
    ) -> TaskRecordEdge? {
        guard let fromID = graph.currentNodeID else { return nil }

        let toNode = graph.addOrMergeNode(TaskRecord(
            abstractState: toAbstractState,
            planningStateID: toPlanningStateID
        ))

        let edge = TaskRecordEdge(
            fromNodeID: fromID,
            toNodeID: toNode.id,
            action: action,
            actionContractID: actionContractID,
            status: .candidate
        )
        return graph.addEdge(edge)
    }

    /// After a verified execution, record the outcome and advance the graph.
    @discardableResult
    public func recordVerifiedExecution(
        edgeID: String,
        resultWorldState: WorldState,
        latencyMs: Int = 0,
        cost: Double = 0,
        createdByAction: String? = nil
    ) -> TaskRecord {
        let abstract = stateAbstractor.abstractState(from: resultWorldState)
        let resultNode = TaskRecord(
            abstractState: abstract,
            planningStateID: resultWorldState.planningState.id,
            worldSnapshotRef: resultWorldState.observationHash,
            createdByAction: createdByAction
        )
        return graph.recordExecution(
            edgeID: edgeID,
            resultNode: resultNode,
            latencyMs: latencyMs,
            cost: cost
        )
    }

    /// Record a failed execution without advancing the current pointer.
    public func recordFailedExecution(edgeID: String, latencyMs: Int = 0, cost: Double = 0) {
        graph.recordFailure(edgeID: edgeID, latencyMs: latencyMs, cost: cost)
    }

    // MARK: - Query Helpers

    public func currentNode() -> TaskRecord? {
        graph.currentNode()
    }

    /// Recovery alternatives: all non-abandoned edges from the current node
    /// excluding the one that just failed.
    public func recoveryEdges(excludingEdgeID: String) -> [TaskRecordEdge] {
        guard let nodeID = graph.currentNodeID else { return [] }
        return graph.alternateEdges(from: nodeID, excluding: excludingEdgeID)
    }

    // MARK: - Export

    /// Export the graph as a GraphViz DOT string for diagnostics.
    public func exportDOT() -> String {
        var lines = ["digraph TaskLedger {"]
        lines.append("  rankdir=LR;")

        for node in graph.allNodes() {
            let label = "\(node.abstractState.rawValue)\\n(\(node.planningStateID))"
            let style = node.id == graph.currentNodeID ? " style=filled fillcolor=lightblue" : ""
            lines.append("  \"\(node.id)\" [label=\"\(label)\"\(style)];")
        }

        for edge in graph.allEdges() {
            let label = "\(edge.action)\\nP=\(String(format: "%.2f", edge.successProbability))"
            let color: String
            switch edge.status {
            case .executedSuccess: color = "green"
            case .executedFailure: color = "red"
            case .abandoned: color = "gray"
            case .candidate: color = "blue"
            }
            lines.append("  \"\(edge.fromNodeID)\" -> \"\(edge.toNodeID)\" [label=\"\(label)\" color=\(color)];")
        }

        lines.append("}")
        return lines.joined(separator: "\n")
    }

    /// Export the graph as a JSON-serialisable dictionary for diagnostics.
    public func exportJSON() -> [String: Any] {
        let nodeList = graph.allNodes().map { node -> [String: Any] in
            [
                "id": node.id,
                "abstractState": node.abstractState.rawValue,
                "planningStateID": node.planningStateID.rawValue,
                "visitCount": node.visitCount,
                "confidence": node.confidence,
                "isCurrent": node.id == graph.currentNodeID,
            ]
        }
        let allEdges = graph.allEdges()
        let edgeList = allEdges.map { edge -> [String: Any] in
            [
                "id": edge.id,
                "from": edge.fromNodeID,
                "to": edge.toNodeID,
                "action": edge.action,
                "status": edge.status.rawValue,
                "successProbability": edge.successProbability,
                "attempts": edge.attempts,
            ]
        }
        let edgeSuccessRates: [String: Any] = Dictionary(
            uniqueKeysWithValues: allEdges.filter { $0.attempts > 0 }.map { edge in
                (edge.id, [
                    "action": edge.action,
                    "success_rate": edge.successProbability,
                    "attempts": edge.attempts,
                    "success_count": edge.successCount,
                    "failure_count": edge.failureCount,
                ] as [String: Any])
            }
        )
        let currentNodeIDValue = graph.currentNodeID ?? ""
        return [
            "currentNodeID": currentNodeIDValue,
            "nodes": nodeList,
            "edges": edgeList,
            // Phase 1 diagnostic fields (snake_case per diagnostics convention)
            "current_node": currentNodeIDValue,
            "edge_success_rates": edgeSuccessRates,
        ]
    }
}
