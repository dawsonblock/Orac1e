import Foundation

/// Defines the baseline metric thresholds for benchmark gating.
///
/// Future runtime refactors must not degrade these metrics beyond
/// the tolerance defined here.  Run evals on every major change and
/// compare against these baselines.
public struct BenchmarkBaseline: Codable, Sendable {

    /// Minimum acceptable task success rate (0.0–1.0).
    public let minimumSuccessRate: Double

    /// Maximum acceptable average steps per task.
    public let maximumAverageSteps: Double

    /// Maximum acceptable recovery count per task.
    public let maximumRecoveryCount: Int

    /// Maximum acceptable wrong-target rate (0.0–1.0).
    public let maximumWrongTargetRate: Double

    /// Minimum acceptable patch success rate (0.0–1.0).
    public let minimumPatchSuccessRate: Double

    /// Maximum acceptable regression rate (0.0–1.0).
    public let maximumRegressionRate: Double

    public init(
        minimumSuccessRate: Double = 0.7,
        maximumAverageSteps: Double = 20.0,
        maximumRecoveryCount: Int = 3,
        maximumWrongTargetRate: Double = 0.1,
        minimumPatchSuccessRate: Double = 0.5,
        maximumRegressionRate: Double = 0.05
    ) {
        self.minimumSuccessRate = minimumSuccessRate
        self.maximumAverageSteps = maximumAverageSteps
        self.maximumRecoveryCount = maximumRecoveryCount
        self.maximumWrongTargetRate = maximumWrongTargetRate
        self.minimumPatchSuccessRate = minimumPatchSuccessRate
        self.maximumRegressionRate = maximumRegressionRate
    }

    /// The default baseline for the current release.
    public static let current = BenchmarkBaseline()

    /// Check whether a metrics snapshot meets the baseline.
    public func isMet(
        successRate: Double,
        averageSteps: Double,
        recoveryCount: Int,
        wrongTargetRate: Double,
        patchSuccessRate: Double,
        regressionRate: Double
    ) -> BaselineResult {
        var violations: [String] = []
        if successRate < minimumSuccessRate {
            violations.append("successRate \(successRate) < \(minimumSuccessRate)")
        }
        if averageSteps > maximumAverageSteps {
            violations.append("averageSteps \(averageSteps) > \(maximumAverageSteps)")
        }
        if recoveryCount > maximumRecoveryCount {
            violations.append("recoveryCount \(recoveryCount) > \(maximumRecoveryCount)")
        }
        if wrongTargetRate > maximumWrongTargetRate {
            violations.append("wrongTargetRate \(wrongTargetRate) > \(maximumWrongTargetRate)")
        }
        if patchSuccessRate < minimumPatchSuccessRate {
            violations.append("patchSuccessRate \(patchSuccessRate) < \(minimumPatchSuccessRate)")
        }
        if regressionRate > maximumRegressionRate {
            violations.append("regressionRate \(regressionRate) > \(maximumRegressionRate)")
        }
        return BaselineResult(passed: violations.isEmpty, violations: violations)
    }
}

/// The result of checking metrics against the benchmark baseline.
public struct BaselineResult: Sendable {
    public let passed: Bool
    public let violations: [String]

    public init(passed: Bool, violations: [String] = []) {
        self.passed = passed
        self.violations = violations
    }
}
