import Foundation
import CoreGraphics

public struct UnifiedElement: Sendable, Codable, Identifiable {

    public let id: String
    public let source: ElementSource

    public let role: String?
    public let label: String?
    public let value: String?

    public let frame: CGRect?

    public let enabled: Bool
    public let visible: Bool
    public let focused: Bool

    public let confidence: Double

    public init(
        id: String,
        source: ElementSource,
        role: String? = nil,
        label: String? = nil,
        value: String? = nil,
        frame: CGRect? = nil,
        enabled: Bool = true,
        visible: Bool = true,
        focused: Bool = false,
        confidence: Double = 1.0
    ) {
        self.id = id
        self.source = source
        self.role = role
        self.label = label
        self.value = value
        self.frame = frame
        self.enabled = enabled
        self.visible = visible
        self.focused = focused
        self.confidence = confidence
    }

    public func toDict() -> [String: Any] {
        var result: [String: Any] = [
            "id": id,
            "source": source.rawValue,
            "enabled": enabled,
            "visible": visible,
            "focused": focused,
            "confidence": confidence,
        ]

        if let role {
            result["role"] = role
        }
        if let label {
            result["label"] = label
        }
        if let value {
            result["value"] = value
        }
        if let frame {
            result["frame"] = [
                "x": frame.origin.x,
                "y": frame.origin.y,
                "width": frame.width,
                "height": frame.height,
            ]
        }

        return result
    }
}
