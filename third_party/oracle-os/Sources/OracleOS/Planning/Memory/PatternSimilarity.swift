import Foundation

public struct PatternSimilarity: Sendable {
    public let score: Double
    public let matchedSignals: [String]
    public let source: PatternSimilaritySource

    public init(
        score: Double,
        matchedSignals: [String] = [],
        source: PatternSimilaritySource = .actionSequence
    ) {
        self.score = min(max(score, 0), 1)
        self.matchedSignals = matchedSignals
        self.source = source
    }
}

public enum PatternSimilaritySource: String, Sendable {
    case actionSequence = "action_sequence"
    case taskFamily = "task_family"
    case errorSignature = "error_signature"
    case outcomeShape = "outcome_shape"
    case targetHistory = "target_history"
}

public enum PatternSimilarityCalculator {

    public static func similarity(
        between lhs: [String],
        and rhs: [String]
    ) -> PatternSimilarity {
        guard !lhs.isEmpty, !rhs.isEmpty else {
            return PatternSimilarity(score: 0, matchedSignals: ["empty sequence"])
        }

        let lhsSet = Set(lhs)
        let rhsSet = Set(rhs)
        let intersection = lhsSet.intersection(rhsSet)

        guard !intersection.isEmpty else {
            return PatternSimilarity(score: 0, matchedSignals: ["no overlap"])
        }

        let jaccardIndex = Double(intersection.count) / Double(lhsSet.union(rhsSet).count)
        let orderScore = orderSimilarity(lhs: lhs, rhs: rhs)
        let combined = 0.6 * jaccardIndex + 0.4 * orderScore

        var signals: [String] = []
        if jaccardIndex > 0.5 {
            signals.append("high set overlap (\(String(format: "%.2f", jaccardIndex)))")
        }
        if orderScore > 0.5 {
            signals.append("similar ordering (\(String(format: "%.2f", orderScore)))")
        }

        return PatternSimilarity(
            score: combined,
            matchedSignals: signals,
            source: .actionSequence
        )
    }

    public static func taskFamilySimilarity(
        goalA: String,
        goalB: String
    ) -> PatternSimilarity {
        let tokensA = Set(goalA.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let tokensB = Set(goalB.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))

        guard !tokensA.isEmpty, !tokensB.isEmpty else {
            return PatternSimilarity(score: 0, source: .taskFamily)
        }

        let intersection = tokensA.intersection(tokensB)
        let score = Double(intersection.count) / Double(max(tokensA.count, tokensB.count))

        return PatternSimilarity(
            score: score,
            matchedSignals: intersection.sorted(),
            source: .taskFamily
        )
    }

    private static func orderSimilarity(lhs: [String], rhs: [String]) -> Double {
        let minLen = min(lhs.count, rhs.count)
        guard minLen > 0 else { return 0 }
        var matches = 0
        for i in 0..<minLen {
            if lhs[i] == rhs[i] { matches += 1 }
        }
        return Double(matches) / Double(max(lhs.count, rhs.count))
    }
}
