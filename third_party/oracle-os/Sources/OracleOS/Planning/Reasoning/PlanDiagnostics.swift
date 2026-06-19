import Foundation

public struct ScoredPlanSummary: Sendable, Equatable {
    public let operatorNames: [String]
    public let score: Double
    public let reasons: [String]
    public let simulatedSuccessProbability: Double?
    public let simulatedRiskScore: Double?
    public let simulatedFailureMode: String?

    public init(
        operatorNames: [String],
        score: Double,
        reasons: [String] = [],
        simulatedSuccessProbability: Double? = nil,
        simulatedRiskScore: Double? = nil,
        simulatedFailureMode: String? = nil
    ) {
        self.operatorNames = operatorNames
        self.score = score
        self.reasons = reasons
        self.simulatedSuccessProbability = simulatedSuccessProbability
        self.simulatedRiskScore = simulatedRiskScore
        self.simulatedFailureMode = simulatedFailureMode
    }
}

public struct PlanDiagnostics: Sendable, Equatable {
    public let selectedOperatorNames: [String]
    public let candidatePlans: [ScoredPlanSummary]
    public let fallbackReason: String?

    public init(
        selectedOperatorNames: [String] = [],
        candidatePlans: [ScoredPlanSummary] = [],
        fallbackReason: String? = nil
    ) {
        self.selectedOperatorNames = selectedOperatorNames
        self.candidatePlans = candidatePlans
        self.fallbackReason = fallbackReason
    }
}
