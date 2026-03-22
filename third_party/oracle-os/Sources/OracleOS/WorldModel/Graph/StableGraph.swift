import Foundation

public final class StableGraph: @unchecked Sendable {
    public private(set) var nodes: [PlanningStateID: StateNode]
    public private(set) var edges: [String: EdgeTransition]

    public init(
        nodes: [PlanningStateID: StateNode] = [:],
        edges: [String: EdgeTransition] = [:]
    ) {
        self.nodes = nodes
        self.edges = edges
    }

    public func upsert(_ edge: EdgeTransition) {
        edges[edge.edgeID] = EdgeTransition(
            edgeID: edge.edgeID,
            fromPlanningStateID: edge.fromPlanningStateID,
            toPlanningStateID: edge.toPlanningStateID,
            actionContractID: edge.actionContractID,
            agentKind: edge.agentKind,
            domain: edge.domain,
            workspaceRelativePath: edge.workspaceRelativePath,
            commandCategory: edge.commandCategory,
            plannerFamily: edge.plannerFamily,
            postconditionClass: edge.postconditionClass,
            attempts: edge.attempts,
            successes: edge.successes,
            latencyTotalMs: edge.latencyTotalMs,
            failureHistogram: edge.failureHistogram,
            lastSuccessTimestamp: edge.lastSuccessTimestamp,
            lastAttemptTimestamp: edge.lastAttemptTimestamp,
            recentOutcomes: edge.recentOutcomes,
            ambiguityTotal: edge.ambiguityTotal,
            recoveryTagged: edge.recoveryTagged,
            approvalRequired: edge.approvalRequired,
            approvalOutcome: edge.approvalOutcome,
            knowledgeTier: .stable
        )
        ensureNode(edge.fromPlanningStateID)
        ensureNode(edge.toPlanningStateID)
    }

    public func remove(edgeID: String) {
        edges.removeValue(forKey: edgeID)
    }

    public func outgoing(from planningStateID: PlanningStateID) -> [EdgeTransition] {
        edges.values
            .filter { $0.fromPlanningStateID == planningStateID }
            .sorted { $0.cost < $1.cost }
    }

    private func ensureNode(_ id: PlanningStateID) {
        if nodes[id] == nil {
            nodes[id] = StateNode(id: id, visitCount: 0)
        }
    }
}
