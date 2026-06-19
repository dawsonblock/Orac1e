import Foundation

public struct Observation: Sendable, Codable {

    public let timestamp: Date

    public let app: String?
    public let windowTitle: String?
    public let url: String?
    public let focusedElementID: String?
    public let elements: [UnifiedElement]

    public init(
        app: String? = nil,
        windowTitle: String? = nil,
        url: String? = nil,
        focusedElementID: String? = nil,
        elements: [UnifiedElement] = []
    ) {
        self.timestamp = Date()
        self.app = app
        self.windowTitle = windowTitle
        self.url = url
        self.focusedElementID = focusedElementID
        self.elements = elements
    }

    public func stableHash() -> String {
        ObservationHash.hash(self)
    }

    public var focusedElement: UnifiedElement? {
        guard let focusedElementID else { return nil }
        return elements.first(where: { $0.id == focusedElementID })
    }

    public func toDict() -> [String: Any] {
        var result: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: timestamp),
            "elements": elements.map { $0.toDict() },
        ]

        if let app {
            result["app"] = app
        }
        if let windowTitle {
            result["window_title"] = windowTitle
        }
        if let url {
            result["url"] = url
        }
        if let focusedElementID {
            result["focused_element_id"] = focusedElementID
        }
        if let focusedElement {
            result["focused_element"] = focusedElement.toDict()
        }

        return result
    }
}
