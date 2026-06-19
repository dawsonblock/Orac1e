import Foundation

public struct BrowserPageMatch: Sendable, Equatable {
    public let element: PageIndexedElement
    public let score: Double
    public let reasons: [String]
}

public enum BrowserPageQuery {
    public static func query(
        snapshot: PageSnapshot,
        text: String?,
        role: String? = nil
    ) -> [BrowserPageMatch] {
        let normalizedText = text?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return snapshot.indexedElements.compactMap { element in
            var score = 0.0
            var reasons: [String] = []

            if let normalizedText, !normalizedText.isEmpty {
                let haystacks = [element.label, element.value, element.domID, element.tag].compactMap { $0?.lowercased() }
                if haystacks.contains(where: { $0 == normalizedText }) {
                    score += 0.7
                    reasons.append("exact browser element match")
                } else if haystacks.contains(where: { $0.contains(normalizedText) }) {
                    score += 0.45
                    reasons.append("partial browser element match")
                } else {
                    return nil
                }
            }

            if let role, let elementRole = element.role, elementRole.lowercased().contains(role.lowercased()) {
                score += 0.2
                reasons.append("role match")
            }

            if element.focused {
                score += 0.05
                reasons.append("already focused")
            }
            if element.enabled {
                score += 0.05
                reasons.append("enabled")
            }

            return BrowserPageMatch(element: element, score: min(score, 1), reasons: reasons)
        }
        .sorted { lhs, rhs in lhs.score > rhs.score }
    }
}
