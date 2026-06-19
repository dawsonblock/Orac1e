import Foundation

public struct PathScorer: Sendable {
    public init() {}

    public func score(
        edge: EdgeTransition,
        actionContract: ActionContract?,
        goal: Goal,
        memoryBias: Double = 0,
        riskPenalty: Double = 0
    ) -> Double {
        let successScore = edge.successRate
        let recencyScore = normalizedRecency(edge.lastSuccessTimestamp ?? edge.lastAttemptTimestamp)
        let boundedMemoryBias = max(0, min(1, memoryBias))
        let latencyScore = max(0, 1 - min(edge.averageLatencyMs / 2_000.0, 1))
        let boundedRiskPenalty = max(0, min(0.25, riskPenalty))

        return (0.4 * successScore)
            + (0.3 * recencyScore)
            + (0.2 * boundedMemoryBias)
            + (0.1 * latencyScore)
            - boundedRiskPenalty
    }

    private func normalizedRecency(_ timestamp: TimeInterval?) -> Double {
        guard let timestamp else { return 0 }
        let age = max(Date().timeIntervalSince1970 - timestamp, 0)
        let sevenDays: Double = 7 * 24 * 60 * 60
        return max(0, 1 - min(age / sevenDays, 1))
    }
}
