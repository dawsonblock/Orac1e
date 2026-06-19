import CryptoKit
import Foundation

public enum ObservationHash {
    public static func hash(_ observation: Observation) -> String {
        let normalized = NormalizedObservation(observation: observation)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        guard let data = try? encoder.encode(normalized) else {
            return "observation-hash-error"
        }

        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct NormalizedObservation: Codable {
    let app: String?
    let windowTitle: String?
    let url: String?
    let focusedElementID: String?
    let elements: [NormalizedElement]

    init(observation: Observation) {
        self.app = observation.app
        self.windowTitle = observation.windowTitle
        self.url = observation.url
        self.focusedElementID = observation.focusedElementID
        self.elements = observation.elements
            .sorted { $0.id < $1.id }
            .map(NormalizedElement.init)
    }
}

private struct NormalizedElement: Codable {
    let id: String
    let source: String
    let role: String?
    let label: String?
    let value: String?
    let enabled: Bool
    let visible: Bool
    let focused: Bool
    let confidence: Double

    init(_ element: UnifiedElement) {
        self.id = element.id
        self.source = element.source.rawValue
        self.role = element.role
        self.label = element.label
        self.value = element.value
        self.enabled = element.enabled
        self.visible = element.visible
        self.focused = element.focused
        self.confidence = element.confidence
    }
}
