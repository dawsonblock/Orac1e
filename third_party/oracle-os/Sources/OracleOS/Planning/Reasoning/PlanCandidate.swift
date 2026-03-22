import Foundation

public struct PlanCandidate: Sendable {
    public let operators: [Operator]
    public let projectedState: ReasoningPlanningState
    public let score: Double
    public let reasons: [String]
    public let simulatedOutcome: SimulatedOutcome?
    public let estimatedCost: Double
    public let riskScore: Double
    public let successProbability: Double
    public let sourceType: PlanSourceType
    /// The operator families used by this plan's operators.
    public let operatorFamilies: [OperatorFamily]

    public init(
        operators: [Operator],
        projectedState: ReasoningPlanningState,
        score: Double = 0,
        reasons: [String] = [],
        simulatedOutcome: SimulatedOutcome? = nil,
        estimatedCost: Double? = nil,
        riskScore: Double? = nil,
        successProbability: Double? = nil,
        sourceType: PlanSourceType = .reasoning
    ) {
        self.operators = operators
        self.projectedState = projectedState
        self.score = score
        self.reasons = reasons
        self.simulatedOutcome = simulatedOutcome
        self.estimatedCost = estimatedCost ?? operators.reduce(0.0) { $0 + $1.baseCost }
        self.riskScore = riskScore ?? operators.reduce(0.0) { $0 + $1.risk } / Double(max(operators.count, 1))
        self.successProbability = successProbability ?? simulatedOutcome?.successProbability ?? 0
        self.sourceType = sourceType
        self.operatorFamilies = Array(Set(operators.map(\.kind.operatorFamily)))
    }

    /// Returns true if all operators in this plan use families allowed by the strategy.
    public func isAllowed(by strategy: SelectedStrategy) -> Bool {
        operatorFamilies.allSatisfy { strategy.allows($0) }
    }
}
