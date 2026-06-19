import Foundation

public final class CandidateGraph: @unchecked Sendable {
    public var nodes: [PlanningStateID: StateNode]
    public var edges: [String: EdgeTransition]

    public init(
        nodes: [PlanningStateID: StateNode] = [:],
        edges: [String: EdgeTransition] = [:]
    ) {
        self.nodes = nodes
        self.edges = edges
    }

    public func record(_ transition: VerifiedTransition) {
        ensureNode(transition.fromPlanningStateID)
        ensureNode(transition.toPlanningStateID)

        let key = edgeKey(
            from: transition.fromPlanningStateID,
            actionContractID: transition.actionContractID,
            postconditionClass: transition.postconditionClass
        )

        let edge = edges[key] ?? EdgeTransition(
            edgeID: key,
            fromPlanningStateID: transition.fromPlanningStateID,
            toPlanningStateID: transition.toPlanningStateID,
            actionContractID: transition.actionContractID,
            agentKind: transition.agentKind,
            domain: transition.domain,
            workspaceRelativePath: transition.workspaceRelativePath,
            commandCategory: transition.commandCategory,
            plannerFamily: transition.plannerFamily,
            postconditionClass: transition.postconditionClass,
            knowledgeTier: transition.knowledgeTier
        )

        edge.record(transition)
        edges[key] = edge
    }

    private func ensureNode(_ id: PlanningStateID) {
        if let node = nodes[id] {
            node.visitCount += 1
        } else {
            nodes[id] = StateNode(id: id, visitCount: 1)
        }
    }

    private func edgeKey(
        from planningStateID: PlanningStateID,
        actionContractID: String,
        postconditionClass: PostconditionClass
    ) -> String {
        [
            planningStateID.rawValue,
            actionContractID,
            postconditionClass.rawValue,
        ].joined(separator: "|")
    }
}
