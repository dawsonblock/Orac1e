import Foundation

public enum WorldQueryResolutionError: Error, Sendable, Equatable {
    case notFound(String)
    case ambiguous(String, Double)
    case lowConfidence(String, Double)

    public var failureClass: FailureClass {
        switch self {
        case .notFound:
            return .elementNotFound
        case .ambiguous, .lowConfidence:
            return .elementAmbiguous
        }
    }
}

public extension WorldState {

    func find(
        query: ElementQuery
    ) -> ElementCandidate? {

        rankedCandidates(query: query).first
    }

    func rankedCandidates(
        query: ElementQuery,
        memoryStore: UnifiedMemoryStore? = nil
    ) -> [ElementCandidate] {
        ElementRanker.rank(
            elements: observation.elements,
            query: query,
            worldState: self,
            memoryStore: memoryStore
        )
    }

    func resolve(
        query: ElementQuery,
        memoryStore: UnifiedMemoryStore? = nil,
        minimumScore: Double = 0.6,
        maximumAmbiguity: Double = 0.2
    ) throws -> ElementCandidate {
        let ranked = rankedCandidates(query: query, memoryStore: memoryStore)
        guard let best = ranked.first else {
            throw WorldQueryResolutionError.notFound(query.text ?? query.role ?? "unknown")
        }
        guard best.score >= minimumScore else {
            throw WorldQueryResolutionError.lowConfidence(
                query.text ?? query.role ?? "unknown",
                best.score
            )
        }
        guard best.ambiguityScore <= maximumAmbiguity else {
            throw WorldQueryResolutionError.ambiguous(
                query.text ?? query.role ?? "unknown",
                best.ambiguityScore
            )
        }
        return best
    }

}
