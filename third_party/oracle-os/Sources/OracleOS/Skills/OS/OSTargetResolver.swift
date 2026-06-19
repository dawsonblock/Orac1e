import Foundation

enum OSTargetResolver {
    static let minimumScore = 0.6
    static let maximumAmbiguity = 0.2

    static func resolve(
        query: ElementQuery,
        state: WorldState,
        memoryStore: UnifiedMemoryStore
    ) throws -> ElementCandidate {
        do {
            return try state.resolve(
                query: query,
                memoryStore: memoryStore,
                minimumScore: minimumScore,
                maximumAmbiguity: maximumAmbiguity
            )
        } catch let error as WorldQueryResolutionError {
            switch error {
            case let .notFound(label):
                throw SkillResolutionError.noCandidate(label)
            case let .ambiguous(label, ambiguity):
                throw SkillResolutionError.ambiguousTarget(label, ambiguity)
            case let .lowConfidence(label, score):
                throw SkillResolutionError.ambiguousTarget(label, score)
            }
        } catch {
            throw error
        }
    }
}
