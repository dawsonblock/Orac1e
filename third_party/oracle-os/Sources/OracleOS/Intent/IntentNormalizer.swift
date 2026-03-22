import Foundation

/// Normalizes raw user input into a canonical Intent.
public struct IntentNormalizer {
    public init() {}

    public func normalize(raw: String, domain: IntentDomain? = nil) -> Intent {
        let inferredDomain = domain ?? inferDomain(from: raw)
        return Intent(
            domain: inferredDomain,
            objective: raw.trimmingCharacters(in: .whitespacesAndNewlines),
            priority: .normal,
            metadata: [:]
        )
    }

    private func inferDomain(from text: String) -> IntentDomain {
        let lowercased = text.lowercased()
        if lowercased.contains("click") || lowercased.contains("type") || lowercased.contains("focus") {
            return .ui
        } else if lowercased.contains("build") || lowercased.contains("test") || lowercased.contains("file") {
            return .code
        } else if lowercased.contains("open") || lowercased.contains("launch") {
            return .system
        }
        return .mixed
    }
}
