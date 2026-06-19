import Foundation

/// Projects normalized AX nodes into the canonical PerceivedElement model.
/// Output: the world model representation used by planners.
public struct UIWorldProjector {
    private let normalizer: AXTreeNormalizer
    private let classifier: AXActionabilityClassifier

    public init() {
        self.normalizer = AXTreeNormalizer()
        self.classifier = AXActionabilityClassifier()
    }

    public func project(_ rawNodes: [RawPerceivedNode]) -> [PerceivedElement] {
        let normalized = normalizer.normalize(rawNodes)
        return normalized.map { node in
            let score = classifier.classify(node)
            return PerceivedElement(stableID: node.stableID, role: node.role, title: node.title,
                                    frame: node.frame, isVisible: node.isVisible,
                                    isEnabled: node.isEnabled, actions: node.actions,
                                    confidence: score.confidence)
        }
    }
}

/// Canonical world-model element. Stable across AX tree changes.
public struct PerceivedElement: Sendable, Codable {
    public let stableID: String
    public let role: String
    public let title: String?
    public let frame: CGRect?
    public let isVisible: Bool
    public let isEnabled: Bool
    public let actions: [String]
    public let confidence: Double

    public init(stableID: String, role: String, title: String?, frame: CGRect?,
                isVisible: Bool, isEnabled: Bool, actions: [String], confidence: Double) {
        self.stableID = stableID; self.role = role; self.title = title; self.frame = frame
        self.isVisible = isVisible; self.isEnabled = isEnabled; self.actions = actions; self.confidence = confidence
    }
}
