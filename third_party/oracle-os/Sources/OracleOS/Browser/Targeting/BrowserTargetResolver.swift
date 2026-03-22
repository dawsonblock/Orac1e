import Foundation

public struct BrowserTargetSelection: Sendable, Equatable {
    public let match: BrowserPageMatch
    public let ambiguityScore: Double
}

public struct BrowserTargetScore: Sendable {
    public let textSimilarity: Double
    public let roleMatch: Double
    public let visibilityScore: Double
    public let spatialProximity: Double
    public let contextMatch: Double
    public let historicalSuccess: Double
    public let totalScore: Double
    public let notes: [String]

    public init(
        textSimilarity: Double,
        roleMatch: Double,
        visibilityScore: Double,
        spatialProximity: Double = 0,
        contextMatch: Double = 0,
        historicalSuccess: Double = 0,
        notes: [String] = []
    ) {
        self.textSimilarity = textSimilarity
        self.roleMatch = roleMatch
        self.visibilityScore = visibilityScore
        self.spatialProximity = spatialProximity
        self.contextMatch = contextMatch
        self.historicalSuccess = historicalSuccess
        self.totalScore = 0.40 * textSimilarity
            + 0.25 * roleMatch
            + 0.15 * visibilityScore
            + 0.05 * spatialProximity
            + 0.05 * contextMatch
            + 0.10 * historicalSuccess
        self.notes = notes
    }
}

public enum BrowserTargetResolver {
    public static let minimumScore = 0.65
    public static let maximumAmbiguity = 0.15

    public static func resolve(
        query: ElementQuery,
        in snapshot: PageSnapshot,
memoryStore: UnifiedMemoryStore? = nil
    ) throws -> BrowserTargetSelection {
        let matches = BrowserPageQuery.query(snapshot: snapshot, text: query.text, role: query.role)
        guard let best = matches.first else {
            throw SkillResolutionError.noCandidate(query.text ?? query.role ?? "browser target")
        }
        guard best.score >= minimumScore else {
            throw SkillResolutionError.noCandidate(query.text ?? query.role ?? "browser target")
        }

        let secondScore = matches.dropFirst().first?.score ?? 0
        let gap = best.score - secondScore
        // Ambiguity maps the score gap to [0, 1]: a smaller gap between first and
        // second candidates means higher ambiguity. Fail closed when gap < threshold.
        let ambiguity = gap < maximumAmbiguity ? max(0, 1 - gap) : 0
        if gap < maximumAmbiguity {
            throw SkillResolutionError.ambiguousTarget(query.text ?? query.role ?? "browser target", ambiguity)
        }

        return BrowserTargetSelection(match: best, ambiguityScore: ambiguity)
    }

    public static func score(
        query: ElementQuery,
        in snapshot: PageSnapshot,
memoryStore: UnifiedMemoryStore? = nil
    ) -> [BrowserTargetScore] {
        let matches = BrowserPageQuery.query(snapshot: snapshot, text: query.text, role: query.role)
        let memoryBias: Double
        if let store = memoryStore {
            memoryBias = MemoryRouter(memoryStore: store).rankingBias(
                label: query.text,
                app: query.app,
                goalDescription: query.text ?? query.role ?? "",
                repositorySnapshot: nil,
                planningState: nil
            )
        } else {
            memoryBias = 0
        }
        return matches.map { match in
            let textSim = match.score
            let roleMatch: Double = query.role != nil && match.element.role == query.role ? 1.0 : 0.5
            let visibilityScore: Double = 1.0
            var notes: [String] = []
            if textSim >= minimumScore {
                notes.append("strong text match")
            }
            if query.role != nil && match.element.role == query.role {
                notes.append("exact role match")
            }
            if memoryBias > 0 {
                notes.append("memory historical success")
            }
            return BrowserTargetScore(
                textSimilarity: textSim,
                roleMatch: roleMatch,
                visibilityScore: visibilityScore,
                historicalSuccess: min(memoryBias, 1.0),
                notes: notes
            )
        }
    }
}
