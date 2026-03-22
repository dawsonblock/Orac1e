import Foundation

/// Evaluates the effectiveness of a ``TaskStrategy`` after execution by
/// comparing predicted outcomes to actual results. Feeds data back into
/// the meta-reasoning improvement loop.
///
/// Also manages strategy persistence state to prevent per-step thrashing.
public final class StrategyEvaluator: @unchecked Sendable {
    private let lock = NSLock()
    private var evaluations: [StrategyEvaluation] = []

    // MARK: - Strategy persistence state

    private var currentStrategy: SelectedStrategy?
    private var strategyStartStep: Int = 0
    private var stepsSinceSelection: Int = 0

    public init() {}

    // MARK: - Persistence management

    /// Record the current strategy and reset the step counter.
    public func setCurrentStrategy(_ strategy: SelectedStrategy, atStep step: Int = 0) {
        lock.lock()
        defer { lock.unlock() }
        currentStrategy = strategy
        strategyStartStep = step
        stepsSinceSelection = 0
    }

    /// Increment the step counter for the current strategy.
    public func recordStep() {
        lock.lock()
        defer { lock.unlock() }
        stepsSinceSelection += 1
    }

    /// Returns the current strategy if one has been set.
    public func activeStrategy() -> SelectedStrategy? {
        lock.lock()
        defer { lock.unlock() }
        return currentStrategy
    }

    /// Returns the number of steps since the current strategy was selected.
    public func stepsSinceStrategySelection() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return stepsSinceSelection
    }

    /// Determines whether the strategy should be reevaluated based on
    /// current conditions.
    ///
    /// Reevaluation triggers:
    /// - Current plan completes
    /// - A hard failure occurs
    /// - Confidence collapses (below threshold)
    /// - Current task node changes meaningfully
    /// - Reevaluate-after threshold is hit
    public func shouldReevaluate(
        planCompleted: Bool = false,
        hardFailure: Bool = false,
        confidenceCollapsed: Bool = false,
        taskNodeChanged: Bool = false
    ) -> StrategyReevaluationCause? {
        lock.lock()
        defer { lock.unlock() }

        guard let strategy = currentStrategy else {
            return .noActiveStrategy
        }

        if planCompleted {
            return .planCompleted
        }
        if hardFailure {
            return .hardFailure
        }
        if confidenceCollapsed {
            return .confidenceCollapsed
        }
        if taskNodeChanged {
            return .taskNodeChanged
        }
        if stepsSinceSelection >= strategy.reevaluateAfterStepCount {
            return .stepThresholdReached
        }

        return nil
    }

    // MARK: - Evaluation recording

    /// Record the result of executing a strategy for later analysis.
    public func record(_ evaluation: StrategyEvaluation) {
        lock.lock()
        defer { lock.unlock() }
        evaluations.append(evaluation)
    }

    /// Compute an effectiveness score for a strategy kind based on recorded history.
    public func effectiveness(for kind: TaskStrategyKind) -> StrategyEffectivenessScore {
        lock.lock()
        defer { lock.unlock() }

        let relevant = evaluations.filter { $0.strategyKind == kind }
        guard !relevant.isEmpty else {
            return StrategyEffectivenessScore(
                strategyKind: kind,
                sampleCount: 0,
                successRate: 0,
                averageDuration: 0,
                averageRecoveryCount: 0,
                confidenceLevel: 0
            )
        }

        let successes = relevant.filter { $0.succeeded }.count
        let successRate = Double(successes) / Double(relevant.count)
        let avgDuration = relevant.reduce(0.0) { $0 + $1.durationSeconds } / Double(relevant.count)
        let avgRecovery = Double(relevant.reduce(0) { $0 + $1.recoveryCount }) / Double(relevant.count)

        let confidence = min(1.0, Double(relevant.count) * 0.15)

        return StrategyEffectivenessScore(
            strategyKind: kind,
            sampleCount: relevant.count,
            successRate: successRate,
            averageDuration: avgDuration,
            averageRecoveryCount: avgRecovery,
            confidenceLevel: confidence
        )
    }

    /// Returns all recorded evaluations (limited to most recent).
    public func recentEvaluations(limit: Int = 50) -> [StrategyEvaluation] {
        lock.lock()
        defer { lock.unlock() }
        return Array(evaluations.suffix(limit))
    }

    /// Returns strategy kinds sorted by effectiveness (best first).
    public func rankedStrategies() -> [StrategyEffectivenessScore] {
        TaskStrategyKind.allCases
            .map { effectiveness(for: $0) }
            .filter { $0.sampleCount > 0 }
            .sorted { $0.successRate > $1.successRate }
    }
}

/// Reason why the strategy evaluator recommends reevaluation.
public enum StrategyReevaluationCause: String, Sendable {
    case noActiveStrategy = "no_active_strategy"
    case planCompleted = "plan_completed"
    case hardFailure = "hard_failure"
    case confidenceCollapsed = "confidence_collapsed"
    case taskNodeChanged = "task_node_changed"
    case stepThresholdReached = "step_threshold_reached"
}

/// A record of how a strategy performed during a task.
public struct StrategyEvaluation: Sendable {
    public let taskID: String
    public let strategyKind: TaskStrategyKind
    public let succeeded: Bool
    public let durationSeconds: Double
    public let recoveryCount: Int
    public let stepCount: Int
    public let notes: [String]

    public init(
        taskID: String,
        strategyKind: TaskStrategyKind,
        succeeded: Bool,
        durationSeconds: Double = 0,
        recoveryCount: Int = 0,
        stepCount: Int = 0,
        notes: [String] = []
    ) {
        self.taskID = taskID
        self.strategyKind = strategyKind
        self.succeeded = succeeded
        self.durationSeconds = durationSeconds
        self.recoveryCount = recoveryCount
        self.stepCount = stepCount
        self.notes = notes
    }
}

/// Summary of how effective a strategy kind is across observed executions.
public struct StrategyEffectivenessScore: Sendable {
    public let strategyKind: TaskStrategyKind
    public let sampleCount: Int
    public let successRate: Double
    public let averageDuration: Double
    public let averageRecoveryCount: Double
    public let confidenceLevel: Double

    public init(
        strategyKind: TaskStrategyKind,
        sampleCount: Int,
        successRate: Double,
        averageDuration: Double,
        averageRecoveryCount: Double,
        confidenceLevel: Double
    ) {
        self.strategyKind = strategyKind
        self.sampleCount = sampleCount
        self.successRate = successRate
        self.averageDuration = averageDuration
        self.averageRecoveryCount = averageRecoveryCount
        self.confidenceLevel = confidenceLevel
    }
}
