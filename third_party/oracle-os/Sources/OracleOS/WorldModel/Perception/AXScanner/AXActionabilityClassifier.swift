import Foundation
/// Classifies which AX elements are actionable and assigns confidence scores.
public struct AXActionabilityClassifier {
    public init() {}
    public func classify(_ node: NormalizedAXNode) -> ActionabilityScore {
        let actionable = !node.actions.isEmpty && node.isEnabled && node.isVisible
        return ActionabilityScore(stableID: node.stableID, isActionable: actionable, confidence: actionable ? 0.9 : 0.1)
    }
}
public struct ActionabilityScore: Sendable {
    public let stableID: String; public let isActionable: Bool; public let confidence: Double
    public init(stableID: String, isActionable: Bool, confidence: Double) {
        self.stableID = stableID; self.isActionable = isActionable; self.confidence = confidence }
}
