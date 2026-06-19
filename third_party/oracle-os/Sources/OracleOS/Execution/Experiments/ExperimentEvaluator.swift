// ExperimentEvaluator.swift — Task-level scoring and evaluation engine.
//
// Turns raw experiment results and action outcomes into a normalised score
// so the planner can measure progress and the learning loop can decide
// whether to promote or demote strategies.
//
// Pipeline:  execute → artifacts → evaluator → score → planner feedback

import Foundation

// MARK: - Evaluation Score

/// A normalised score produced by the evaluator.  Range: 0.0 (total failure)
/// to 1.0 (complete success).
public struct EvaluationScore: Sendable {
    /// Weighted aggregate score.
    public let overall: Double
    /// Per-dimension breakdown (e.g. "correctness", "efficiency", "safety").
    public let dimensions: [String: Double]
    /// Human-readable explanation of the score.
    public let explanation: String

    public init(overall: Double, dimensions: [String: Double], explanation: String) {
        self.overall = max(0, min(1, overall))
        self.dimensions = dimensions
        self.explanation = explanation
    }
}

// MARK: - Task Outcome

/// Captures the full outcome of a task for evaluation.
public struct TaskOutcome: Sendable {
    public let taskID: String
    public let goalDescription: String
    public let actionResults: [ActionOutcomeSummary]
    public let elapsedMs: Int
    public let artifactCount: Int
    public let postconditionsPassed: Int
    public let postconditionsTotal: Int

    public init(
        taskID: String,
        goalDescription: String,
        actionResults: [ActionOutcomeSummary],
        elapsedMs: Int,
        artifactCount: Int,
        postconditionsPassed: Int,
        postconditionsTotal: Int
    ) {
        self.taskID = taskID
        self.goalDescription = goalDescription
        self.actionResults = actionResults
        self.elapsedMs = elapsedMs
        self.artifactCount = artifactCount
        self.postconditionsPassed = postconditionsPassed
        self.postconditionsTotal = postconditionsTotal
    }
}

/// Lightweight summary of a single action inside a task.
public struct ActionOutcomeSummary: Sendable {
    public let actionName: String
    public let success: Bool
    public let verified: Bool
    public let durationMs: Int

    public init(actionName: String, success: Bool, verified: Bool, durationMs: Int) {
        self.actionName = actionName
        self.success = success
        self.verified = verified
        self.durationMs = durationMs
    }
}

// MARK: - Evaluator

/// Scores task outcomes using configurable dimension weights.
///
/// Default dimensions:
///   - correctness:  postcondition pass rate
///   - efficiency:   inverse of per-action latency normalised against a budget
///   - verification: fraction of actions that were verified
///   - completion:   fraction of actions that succeeded
public struct ExperimentEvaluator: Sendable {

    public struct Weights: Sendable {
        public let correctness: Double
        public let efficiency: Double
        public let verification: Double
        public let completion: Double

        public init(
            correctness: Double = 0.4,
            efficiency: Double = 0.1,
            verification: Double = 0.2,
            completion: Double = 0.3
        ) {
            self.correctness = correctness
            self.efficiency = efficiency
            self.verification = verification
            self.completion = completion
        }
    }

    public let weights: Weights
    /// Per-action latency budget in milliseconds.
    public let latencyBudgetMs: Int

    public init(weights: Weights = Weights(), latencyBudgetMs: Int = 5000) {
        self.weights = weights
        self.latencyBudgetMs = latencyBudgetMs
    }

    /// Evaluate a single task outcome.
    public func evaluate(_ outcome: TaskOutcome) -> EvaluationScore {
        let correctness = outcome.postconditionsTotal > 0
            ? Double(outcome.postconditionsPassed) / Double(outcome.postconditionsTotal)
            : (outcome.actionResults.allSatisfy(\.success) ? 1.0 : 0.0)

        let totalActions = outcome.actionResults.count
        let succeededCount = outcome.actionResults.filter(\.success).count
        let completion = totalActions > 0 ? Double(succeededCount) / Double(totalActions) : 0.0

        let verifiedCount = outcome.actionResults.filter(\.verified).count
        let verification = totalActions > 0 ? Double(verifiedCount) / Double(totalActions) : 0.0

        let avgLatency = totalActions > 0
            ? Double(outcome.actionResults.map(\.durationMs).reduce(0, +)) / Double(totalActions)
            : 0.0
        let efficiency: Double
        if latencyBudgetMs > 0 {
            efficiency = max(0, min(1, 1.0 - (avgLatency / Double(latencyBudgetMs))))
        } else {
            efficiency = 0.0
        }

        let dimensions: [String: Double] = [
            "correctness": correctness,
            "efficiency": efficiency,
            "verification": verification,
            "completion": completion,
        ]

        let overall =
            correctness * weights.correctness
            + efficiency * weights.efficiency
            + verification * weights.verification
            + completion * weights.completion

        let explanation =
            "correctness=\(String(format: "%.2f", correctness)) "
            + "completion=\(String(format: "%.2f", completion)) "
            + "verification=\(String(format: "%.2f", verification)) "
            + "efficiency=\(String(format: "%.2f", efficiency))"

        return EvaluationScore(overall: overall, dimensions: dimensions, explanation: explanation)
    }
}
