import Foundation

public struct GraphStats: Sendable {
    public let attempts: Int
    public let successes: Int
    public let updatedAt: TimeInterval

    public init(attempts: Int, successes: Int, updatedAt: TimeInterval) {
        self.attempts = attempts
        self.successes = successes
        self.updatedAt = updatedAt
    }
}

public final class GraphMaintenance: @unchecked Sendable {
    private let policy: GraphPromotionPolicy
    private let pruner: GraphPruner

    public init(
        policy: GraphPromotionPolicy = GraphPromotionPolicy(),
        pruner: GraphPruner = GraphPruner()
    ) {
        self.policy = policy
        self.pruner = pruner
    }

    public func promoteEligibleEdges(
        candidateGraph: CandidateGraph,
        stableGraph: StableGraph,
        globalVerifiedSuccessRate: Double,
        now: Date
    ) -> [EdgeTransition] {
        guard !policy.promotionsFrozen(globalVerifiedSuccessRate: globalVerifiedSuccessRate) else {
            return []
        }

        var promoted: [EdgeTransition] = []

        for edge in candidateGraph.edges.values where policy.shouldPromote(edge: edge, now: now) {
            stableGraph.upsert(edge)
            promoted.append(edge)
        }

        return promoted
    }

    public func pruneOrDemoteEdges(
        candidateGraph: CandidateGraph,
        stableGraph: StableGraph,
        now: Date
    ) -> [String] {
        pruner.pruneOrDemote(
            candidateGraph: candidateGraph,
            stableGraph: stableGraph,
            policy: policy,
            now: now
        )
    }
}
