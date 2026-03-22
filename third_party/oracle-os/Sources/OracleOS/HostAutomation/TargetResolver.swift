import Foundation

public struct HostTargetSelection: Sendable {
    public let candidate: ElementCandidate
    public let ambiguityScore: Double
    public let notes: [String]

    public init(
        candidate: ElementCandidate,
        ambiguityScore: Double,
        notes: [String] = []
    ) {
        self.candidate = candidate
        self.ambiguityScore = ambiguityScore
        self.notes = notes
    }
}

public enum HostTargetResolver {
    public static let minimumScore = 0.60
    public static let maximumAmbiguity = 0.20

    public static func resolve(
        query: ElementQuery,
        elements: [UnifiedElement],
        worldState: WorldState? = nil,
memoryStore: UnifiedMemoryStore? = nil
    ) throws -> HostTargetSelection {
        let ranked = ElementRanker.rank(
            elements: elements,
            query: query,
            worldState: worldState,
            memoryStore: memoryStore
        )

        guard let best = ranked.first else {
            throw SkillResolutionError.noCandidate(query.text ?? query.role ?? "host target")
        }

        guard best.score >= minimumScore else {
            throw SkillResolutionError.noCandidate(query.text ?? query.role ?? "host target")
        }

        if best.ambiguityScore > maximumAmbiguity {
            throw SkillResolutionError.ambiguousTarget(
                query.text ?? query.role ?? "host target",
                best.ambiguityScore
            )
        }

        var notes: [String] = best.reasons
        if best.score >= 0.9 {
            notes.append("high confidence match")
        }

        return HostTargetSelection(
            candidate: best,
            ambiguityScore: best.ambiguityScore,
            notes: notes
        )
    }

    public static func rank(
        query: ElementQuery,
        elements: [UnifiedElement],
        worldState: WorldState? = nil,
memoryStore: UnifiedMemoryStore? = nil
    ) -> [ElementCandidate] {
        ElementRanker.rank(
            elements: elements,
            query: query,
            worldState: worldState,
            memoryStore: memoryStore
        )
    }
}
