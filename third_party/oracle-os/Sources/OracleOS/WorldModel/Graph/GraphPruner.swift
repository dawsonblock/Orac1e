import Foundation

public struct GraphPruner: Sendable {
    public init() {}

    @discardableResult
    public func pruneOrDemote(
        candidateGraph: CandidateGraph,
        stableGraph: StableGraph,
        policy: GraphPromotionPolicy,
        now: Date
    ) -> [String] {
        var removed: [String] = []

        for stableEdge in stableGraph.edges.values {
            let evaluationEdge = candidateGraph.edges[stableEdge.edgeID] ?? stableEdge
            if candidateGraph.edges[stableEdge.edgeID] != nil {
                stableGraph.upsert(evaluationEdge)
            }
            if policy.shouldPrune(edge: evaluationEdge, now: now) || policy.shouldDemote(edge: evaluationEdge) {
                stableGraph.remove(edgeID: stableEdge.edgeID)
                removed.append(stableEdge.edgeID)
            }
        }

        return removed
    }
}
