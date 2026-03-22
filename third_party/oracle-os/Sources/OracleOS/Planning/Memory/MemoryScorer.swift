import Foundation

public enum MemoryScorer {
    public static func rankingBias(
        control: KnownControl,
        failureCount: Int,
        now: Date = Date()
    ) -> Double {
        guard MemoryPromotionPolicy.allowsDurableBias(
            successes: control.successCount,
            failures: failureCount
        ) else {
            return 0
        }

        let base = min(log(Double(control.successCount) + 1) * 0.05, 0.15)
        return base * MemoryDecayPolicy.freshnessMultiplier(since: control.lastUsed, now: now)
    }

    public static func commandBias(
        successes: Int,
        failures: Int
    ) -> Double {
        guard MemoryPromotionPolicy.allowsDurableBias(
            successes: successes,
            failures: failures
        ) else {
            return 0
        }

        return min(log(Double(successes) + 1) * 0.05, 0.15)
    }

    // Weights reflect relative importance of each memory signal for plan scoring:
    // execution history (0.3) and command patterns (0.2) are strongest indicators,
    // path preferences and fix history (0.1) are secondary signals,
    // experiment preference (0.05) is a weak negative signal,
    // and risk penalty (0.5) is the strongest negative factor.
    // The result is clamped to [-0.3, 0.3] to prevent memory from dominating.
    public static func planBias(influence: MemoryInfluence) -> Double {
        var bias = 0.0
        bias += influence.executionRankingBias * 0.3
        bias += influence.commandBias * 0.2
        if influence.preferredFixPath != nil {
            bias += 0.1
        }
        if influence.shouldPreferExperiments {
            bias -= 0.05
        }
        bias -= influence.riskPenalty * 0.5
        if !influence.avoidedPaths.isEmpty {
            bias -= 0.1
        }
        if !influence.preferredPaths.isEmpty {
            bias += 0.1
        }
        return max(-0.3, min(0.3, bias))
    }

    public static func fixPatternScore(
        pattern: FixPattern,
        now: Date = Date()
    ) -> Double {
        guard MemoryPromotionPolicy.allowsDurableBias(
            successes: pattern.successCount,
            failures: pattern.failureCount
        ) else {
            return 0
        }

        let base = Double(pattern.successCount) - Double(pattern.failureCount) * 0.5
        return max(0, base) * MemoryDecayPolicy.freshnessMultiplier(
            since: pattern.lastAppliedAt,
            now: now
        )
    }
}
