import Foundation

public struct PatternMemoryStore {
    private let store: StrategyMemory

    public init(store: StrategyMemory) {
        self.store = store
    }

    public func preferredFixPath(
        errorSignature: String?,
        now: Date = Date()
    ) -> String? {
        guard let errorSignature, !errorSignature.isEmpty else {
            return nil
        }

        return store.fixPatterns(for: errorSignature)
            .sorted { lhs, rhs in
                let lhsScore = MemoryScorer.fixPatternScore(pattern: lhs, now: now)
                let rhsScore = MemoryScorer.fixPatternScore(pattern: rhs, now: now)
                if lhsScore == rhsScore {
                    return lhs.workspaceRelativePath ?? "" < rhs.workspaceRelativePath ?? ""
                }
                return lhsScore > rhsScore
            }
            .first?
            .workspaceRelativePath
    }

    public func commandBias(
        category: String?,
        workspaceRoot: String?
    ) -> Double {
        guard let category, let workspaceRoot else {
            return 0
        }

        let successes = store.commandSuccessCount(category: category, workspaceRoot: workspaceRoot)
        let failures = store.commandFailureCount(category: category, workspaceRoot: workspaceRoot)
        return MemoryScorer.commandBias(successes: successes, failures: failures)
    }
}
