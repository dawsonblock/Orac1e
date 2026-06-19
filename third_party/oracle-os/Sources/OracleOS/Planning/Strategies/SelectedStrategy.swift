import Foundation

/// The result of strategy selection — the first decision in every planning cycle.
///
/// ``SelectedStrategy`` constrains downstream plan generation by declaring
/// which ``OperatorFamily`` values are allowed. The planner refuses to run
/// without a valid selected strategy.
public struct SelectedStrategy: Sendable, Codable {
    public let kind: StrategyKind
    public let confidence: Double
    public let rationale: String
    public let allowedOperatorFamilies: [OperatorFamily]
    public let reevaluateAfterStepCount: Int

    public init(
        kind: StrategyKind,
        confidence: Double,
        rationale: String,
        allowedOperatorFamilies: [OperatorFamily],
        reevaluateAfterStepCount: Int = 5
    ) {
        self.kind = kind
        self.confidence = confidence
        self.rationale = rationale
        self.allowedOperatorFamilies = allowedOperatorFamilies
        self.reevaluateAfterStepCount = reevaluateAfterStepCount
    }

    /// Returns true if the given operator family is allowed by this strategy.
    public func allows(_ family: OperatorFamily) -> Bool {
        allowedOperatorFamilies.contains(family)
    }
}
