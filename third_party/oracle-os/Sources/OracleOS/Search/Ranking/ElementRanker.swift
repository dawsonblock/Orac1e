import Foundation

public struct ElementRanker {

    public static func rank(
        elements: [UnifiedElement],
        query: ElementQuery,
        worldState: WorldState? = nil,
        memoryStore: UnifiedMemoryStore? = nil
    ) -> [ElementCandidate] {

        var results: [ElementCandidate] = []

        for element in elements {

            let (score, reasons) =
                ElementMatcher.score(
                    element: element,
                    query: query,
                    worldState: worldState,
                    memoryStore: memoryStore
                )

            if score > 0 {

                results.append(
                    ElementCandidate(
                        element: element,
                        score: score,
                        reasons: reasons
                    )
                )
            }
        }

        let sorted = results.sorted { $0.score > $1.score }
        guard let best = sorted.first else {
            return []
        }

        let nextScore = sorted.dropFirst().first?.score ?? 0
        let ambiguityScore = ambiguityScore(bestScore: best.score, nextScore: nextScore)

        return sorted.enumerated().map { index, candidate in
            ElementCandidate(
                element: candidate.element,
                score: candidate.score,
                reasons: candidate.reasons,
                ambiguityScore: index == 0 ? ambiguityScore : 0
            )
        }
    }

    public static func ambiguityScore(bestScore: Double, nextScore: Double) -> Double {
        guard bestScore > 0 else { return 1 }
        let margin = max(bestScore - nextScore, 0)
        return max(0, min(1, 1 - (margin / bestScore)))
    }
}
