import Foundation

public struct PatchRankingSignals: Sendable {
    public let faultLocationConfidence: Double
    public let patchComplexity: Double
    public let coverageImpact: Double
    public let memorySuccessPatterns: Double

    public init(
        faultLocationConfidence: Double = 0,
        patchComplexity: Double = 0,
        coverageImpact: Double = 0,
        memorySuccessPatterns: Double = 0
    ) {
        self.faultLocationConfidence = faultLocationConfidence
        self.patchComplexity = patchComplexity
        self.coverageImpact = coverageImpact
        self.memorySuccessPatterns = memorySuccessPatterns
    }

    public var compositeScore: Double {
        0.40 * faultLocationConfidence
            + 0.25 * (1.0 - patchComplexity)
            + 0.20 * coverageImpact
            + 0.15 * memorySuccessPatterns
    }
}

public struct PatchRanker: Sendable {
    private let comparator: ResultComparator

    public init(comparator: ResultComparator = ResultComparator()) {
        self.comparator = comparator
    }

    public func rank(_ results: [ExperimentResult]) -> [ExperimentResult] {
        comparator.sort(results)
    }

    public func rankWithSignals(
        _ results: [ExperimentResult],
        signals: [String: PatchRankingSignals]
    ) -> [ExperimentResult] {
        let baseRanked = comparator.sort(results)
        return baseRanked.sorted { lhs, rhs in
            let lhsSignals = signals[lhs.candidate.id] ?? PatchRankingSignals()
            let rhsSignals = signals[rhs.candidate.id] ?? PatchRankingSignals()
            let lhsScore = lhsSignals.compositeScore + (lhs.succeeded ? 0.5 : 0)
            let rhsScore = rhsSignals.compositeScore + (rhs.succeeded ? 0.5 : 0)
            return lhsScore > rhsScore
        }
    }
}
