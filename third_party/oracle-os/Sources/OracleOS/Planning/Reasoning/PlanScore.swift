import Foundation

public struct PlanScore: Sendable, Equatable {
    public let predictedSuccess: Double
    public let workflowMatch: Double
    public let stableGraphSupport: Double
    public let memoryBias: Double
    public let riskPenalty: Double
    public let costPenalty: Double
    public let sourceType: PlanSourceType
    public let total: Double
    public let notes: [String]

    public init(
        predictedSuccess: Double = 0,
        workflowMatch: Double = 0,
        stableGraphSupport: Double = 0,
        memoryBias: Double = 0,
        riskPenalty: Double = 0,
        costPenalty: Double = 0,
        sourceType: PlanSourceType = .reasoning,
        notes: [String] = []
    ) {
        self.predictedSuccess = predictedSuccess
        self.workflowMatch = workflowMatch
        self.stableGraphSupport = stableGraphSupport
        self.memoryBias = memoryBias
        self.riskPenalty = riskPenalty
        self.costPenalty = costPenalty
        self.sourceType = sourceType
        self.notes = notes
        self.total = predictedSuccess
            + workflowMatch
            + stableGraphSupport
            + memoryBias
            - riskPenalty
            - costPenalty
    }
}

public enum PlanSourceType: String, Sendable, Codable {
    case workflow
    case stableGraph = "stable_graph"
    case reasoning
    case candidateGraph = "candidate_graph"
    case exploration
    case llm
    case recovery
    case strategy
}
