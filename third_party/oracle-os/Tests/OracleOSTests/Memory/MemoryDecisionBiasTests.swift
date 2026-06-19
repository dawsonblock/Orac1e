import Foundation
import Testing
@testable import OracleOS

@Suite("Memory Decision Bias")
struct MemoryDecisionBiasTests {

    @Test("Memory decision bias aggregates component scores")
    func biasAggregatesComponents() {
        let bias = MemoryDecisionBias(
            successPatternBias: 0.12,
            failurePatternPenalty: 0.05,
            projectSpecificBias: 0.08,
            recentTraceBias: 0.04,
            notes: ["test bias"]
        )

        #expect(bias.totalBias > 0)
        let expected = 0.12 - 0.05 + 0.08 + 0.04
        #expect(abs(bias.totalBias - expected) < 0.001)
    }

    @Test("Zero memory bias has zero total")
    func zeroBiasHasZeroTotal() {
        let bias = MemoryDecisionBias()
        #expect(bias.totalBias == 0)
    }

    @Test("Failure penalty reduces total bias")
    func failurePenaltyReducesBias() {
        let positive = MemoryDecisionBias(
            successPatternBias: 0.2,
            failurePatternPenalty: 0,
            notes: ["positive"]
        )
        let penalized = MemoryDecisionBias(
            successPatternBias: 0.2,
            failurePatternPenalty: 0.15,
            notes: ["penalized"]
        )
        #expect(positive.totalBias > penalized.totalBias)
    }

    @Test("Pattern similarity computes Jaccard-based score")
    func patternSimilarityComputesScore() {
        let similarity = PatternSimilarityCalculator.similarity(
            between: ["click", "type", "submit"],
            and: ["click", "type", "submit"]
        )
        #expect(similarity.score > 0.9)
    }

    @Test("Pattern similarity handles disjoint sequences")
    func patternSimilarityHandlesDisjoint() {
        let similarity = PatternSimilarityCalculator.similarity(
            between: ["click", "scroll"],
            and: ["type", "submit"]
        )
        #expect(similarity.score == 0)
    }

    @Test("Task family similarity matches on shared goal tokens")
    func taskFamilySimilarityMatchesGoalTokens() {
        let similarity = PatternSimilarityCalculator.taskFamilySimilarity(
            goalA: "fix the calculator test failure",
            goalB: "fix the parser test failure"
        )
        #expect(similarity.score > 0)
        #expect(similarity.source == .taskFamily)
    }

    @Test("Pattern similarity score is bounded between 0 and 1")
    func similarityScoreIsBounded() {
        let similarity = PatternSimilarity(score: 1.5, matchedSignals: ["overflow"])
        #expect(similarity.score <= 1.0)
        let negative = PatternSimilarity(score: -0.5)
        #expect(negative.score >= 0.0)
    }
}
