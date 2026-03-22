import Foundation

public struct ElementMatcher {

    public static func score(
        element: UnifiedElement,
        query: ElementQuery,
        worldState: WorldState? = nil,
        memoryStore: UnifiedMemoryStore? = nil
    ) -> (Double, [String]) {

        var score: Double = 0
        var reasons: [String] = []

        if query.visibleOnly && !element.visible {
            return (0, ["not visible"])
        }

        guard element.enabled else {
            return (0, ["disabled"])
        }

        let semanticSimilarity = semanticSimilarity(element: element, query: query)
        if semanticSimilarity > 0 {
            score += semanticSimilarity * 0.4
            reasons.append(semanticSimilarity >= 0.8 ? "strong semantic match" : "semantic match")
        }

        let roleScore = roleMatch(element: element, query: query)
        if roleScore > 0 {
            score += roleScore * 0.2
            reasons.append("role match")
        }

        let sourceTrust = sourceTrust(for: element.source)
        score += sourceTrust * 0.1
        reasons.append("source trust \(element.source.rawValue)")

        let contextMatch = contextMatch(element: element, query: query, worldState: worldState)
        if contextMatch > 0 {
            score += contextMatch * 0.15
            reasons.append("context match")
        }

        let localUIContext = localUIContext(element: element, worldState: worldState)
        if localUIContext > 0 {
            score += localUIContext * 0.05
            reasons.append("local UI context")
        }

        if let memoryStore {
            let memoryBias = MemoryRouter(memoryStore: memoryStore).rankingBias(
                label: element.label,
                app: worldState?.observation.app ?? query.app,
                goalDescription: query.text ?? query.role ?? "",
                repositorySnapshot: worldState?.repositorySnapshot,
                planningState: worldState?.planningState
            )
            if memoryBias > 0 {
                score += memoryBias
                reasons.append("memory bias")
            }
        }

        score += min(max(element.confidence, 0), 1) * 0.1

        return (score, reasons)
    }

    private static func semanticSimilarity(
        element: UnifiedElement,
        query: ElementQuery
    ) -> Double {
        guard let text = query.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else {
            return 0
        }

        let queryTokens = Set(text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
        let labelTokens = Set((element.label ?? "").lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
        let valueTokens = Set((element.value ?? "").lowercased().split(whereSeparator: \.isWhitespace).map(String.init))

        if element.label?.lowercased() == text.lowercased() {
            return 1
        }

        let labelOverlap = Double(queryTokens.intersection(labelTokens).count) / Double(max(queryTokens.count, 1))
        let valueOverlap = Double(queryTokens.intersection(valueTokens).count) / Double(max(queryTokens.count, 1))
        return max(labelOverlap, valueOverlap)
    }

    private static func roleMatch(
        element: UnifiedElement,
        query: ElementQuery
    ) -> Double {
        let role = element.role?.lowercased() ?? ""

        if let queryRole = query.role?.lowercased(), role == queryRole {
            return 1
        }

        if query.clickable == true, role.contains("button") {
            return 0.8
        }

        if query.editable == true, role.contains("text") {
            return 0.8
        }

        return 0
    }

    private static func contextMatch(
        element: UnifiedElement,
        query: ElementQuery,
        worldState: WorldState?
    ) -> Double {
        var total: Double = 0

        if let app = query.app?.lowercased(),
           worldState?.observation.app?.lowercased().contains(app) == true {
            total += 0.5
        }

        if worldState?.planningState.focusedRole == element.role {
            total += 0.25
        }

        if let taskPhase = worldState?.planningState.taskPhase?.lowercased(),
           let queryText = query.text?.lowercased(),
           !taskPhase.isEmpty,
           queryText.contains(taskPhase) {
            total += 0.25
        }

        return min(total, 1)
    }

    private static func localUIContext(
        element: UnifiedElement,
        worldState: WorldState?
    ) -> Double {
        guard let focused = worldState?.observation.focusedElement,
              let elementFrame = element.frame,
              let focusedFrame = focused.frame
        else {
            return 0
        }

        let dx = elementFrame.midX - focusedFrame.midX
        let dy = elementFrame.midY - focusedFrame.midY
        let distance = sqrt((dx * dx) + (dy * dy))
        let normalizedDistance = min(distance / 600.0, 1.0)
        return max(0, 1 - normalizedDistance)
    }

    private static func sourceTrust(for source: ElementSource) -> Double {
        switch source {
        case .ax:
            return 1
        case .fused:
            return 0.95
        case .cdp:
            return 0.85
        case .vision:
            return 0.6
        }
    }
}
