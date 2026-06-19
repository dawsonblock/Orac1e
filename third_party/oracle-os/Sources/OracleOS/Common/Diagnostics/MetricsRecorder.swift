// MetricsRecorder.swift — Real runtime performance metrics.
//
// Tracks measurable runtime performance data including action
// attempts, successes, wrong-target rates, patch metrics, retries,
// and recovery counts. Metrics can be persisted to a JSON file for
// later inspection and analysis.

import Foundation

/// Records runtime performance metrics for benchmark gating.
///
/// Core metrics tracked:
/// - **Task success rate**: actions succeeded / actions attempted
/// - **Average steps**: mean actions per task
/// - **Recovery count**: number of recovery interventions
/// - **Wrong-target rate**: actions hitting unintended targets
/// - **Patch success rate**: patches that pass validation
/// - **Regression rate**: patches that introduce new failures
///
/// These metrics form the baseline for evidence-driven upgrades.
/// Merges that degrade core metrics should be blocked until
/// the regression is understood and addressed.

/// Aggregated runtime performance metrics.
///
/// Every search cycle produces an update to these counters so that
/// runtime performance can be measured and compared across runs.
public struct RuntimeMetrics: Sendable, Codable {
    /// Total actions attempted across all cycles.
    public var actionsAttempted: Int
    /// Total actions that succeeded verification.
    public var actionsSucceeded: Int
    /// Total actions that hit the wrong target.
    public var wrongTargetCount: Int
    /// Total patch generation attempts.
    public var patchAttempts: Int
    /// Total patches that passed verification.
    public var patchSuccesses: Int
    /// Total number of retries across all tasks.
    public var retries: Int
    /// Total number of recovery cycles triggered.
    public var recoveryCount: Int
    /// Cumulative elapsed time in milliseconds for all actions.
    public var totalElapsedMs: Double
    /// Total number of search cycles completed.
    public var searchCycles: Int
    /// Total number of candidates generated.
    public var candidatesGenerated: Int
    /// Total number of candidates from memory.
    public var memoryCandidates: Int
    /// Total number of candidates from graph.
    public var graphCandidates: Int
    /// Total number of candidates from LLM fallback.
    public var llmFallbackCandidates: Int
    /// Timestamp of the last recording.
    public var lastUpdated: TimeInterval

    public init() {
        self.actionsAttempted = 0
        self.actionsSucceeded = 0
        self.wrongTargetCount = 0
        self.patchAttempts = 0
        self.patchSuccesses = 0
        self.retries = 0
        self.recoveryCount = 0
        self.totalElapsedMs = 0
        self.searchCycles = 0
        self.candidatesGenerated = 0
        self.memoryCandidates = 0
        self.graphCandidates = 0
        self.llmFallbackCandidates = 0
        self.lastUpdated = Date().timeIntervalSince1970
    }

    /// Action success rate (0–1).
    public var actionSuccessRate: Double {
        guard actionsAttempted > 0 else { return 0 }
        return Double(actionsSucceeded) / Double(actionsAttempted)
    }

    /// Wrong-target rate (0–1).
    public var wrongTargetRate: Double {
        guard actionsAttempted > 0 else { return 0 }
        return Double(wrongTargetCount) / Double(actionsAttempted)
    }

    /// Patch success rate (0–1).
    public var patchSuccessRate: Double {
        guard patchAttempts > 0 else { return 0 }
        return Double(patchSuccesses) / Double(patchAttempts)
    }

    /// Mean time per action in milliseconds.
    public var meanTimePerAction: Double {
        guard actionsAttempted > 0 else { return 0 }
        return totalElapsedMs / Double(actionsAttempted)
    }
}

/// Records and persists runtime performance metrics.
///
/// Thread-safety: Callers must serialise writes. The recorder is
/// designed to be owned by the runtime and updated after each
/// search cycle or action execution.
public final class MetricsRecorder: @unchecked Sendable {
    private var metrics: RuntimeMetrics
    private let outputPath: String?

    /// Create a recorder that persists metrics to the given path.
    ///
    /// - Parameter outputPath: File path for the JSON metrics file.
    ///   Pass `nil` to record in-memory only (useful for tests).
    public init(outputPath: String? = nil) {
        self.metrics = RuntimeMetrics()
        self.outputPath = outputPath
    }

    /// Current snapshot of all metrics.
    public var current: RuntimeMetrics { metrics }

    // MARK: - Recording

    /// Record the outcome of a single action execution.
    public func recordAction(
        success: Bool,
        wrongTarget: Bool = false,
        elapsedMs: Double = 0,
        isPatch: Bool = false,
        isRetry: Bool = false,
        isRecovery: Bool = false
    ) {
        metrics.actionsAttempted += 1
        if success { metrics.actionsSucceeded += 1 }
        if wrongTarget { metrics.wrongTargetCount += 1 }
        metrics.totalElapsedMs += elapsedMs
        if isPatch {
            metrics.patchAttempts += 1
            if success { metrics.patchSuccesses += 1 }
        }
        if isRetry { metrics.retries += 1 }
        if isRecovery { metrics.recoveryCount += 1 }
        metrics.lastUpdated = Date().timeIntervalSince1970
    }

    /// Record the outcome of a search cycle.
    public func recordSearchCycle(
        candidatesGenerated: Int,
        memoryCandidates: Int = 0,
        graphCandidates: Int = 0,
        llmFallbackCandidates: Int = 0
    ) {
        metrics.searchCycles += 1
        metrics.candidatesGenerated += candidatesGenerated
        metrics.memoryCandidates += memoryCandidates
        metrics.graphCandidates += graphCandidates
        metrics.llmFallbackCandidates += llmFallbackCandidates
        metrics.lastUpdated = Date().timeIntervalSince1970
    }

    // MARK: - Persistence

    /// Write the current metrics to disk as JSON.
    ///
    /// - Throws: If the file cannot be written.
    public func persist() throws {
        guard let outputPath else { return }
        let encoder = OracleJSONCoding.makeEncoder(outputFormatting: [.prettyPrinted, .sortedKeys])
        let data = try encoder.encode(metrics)
        let url = URL(fileURLWithPath: outputPath)
        try data.write(to: url, options: .atomic)
    }

    /// Load previously persisted metrics from disk.
    ///
    /// - Throws: If the file cannot be read or decoded.
    public func load() throws {
        guard let outputPath else { return }
        let url = URL(fileURLWithPath: outputPath)
        guard FileManager.default.fileExists(atPath: outputPath) else { return }
        let data = try Data(contentsOf: url)
        metrics = try OracleJSONCoding.makeDecoder().decode(RuntimeMetrics.self, from: data)
    }

    /// Reset all metrics to zero.
    public func reset() {
        metrics = RuntimeMetrics()
    }
}
