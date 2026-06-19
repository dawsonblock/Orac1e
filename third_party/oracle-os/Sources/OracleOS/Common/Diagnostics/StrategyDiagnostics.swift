import Foundation

/// Records strategy selection diagnostics for every planning cycle.
///
/// Captures the selected strategy, confidence, rationale, allowed operator
/// families, candidate counts before/after filtering, and reevaluation causes.
/// Diagnostics are written to ``strategy_selection.jsonl``.
public struct StrategyDiagnostics: Sendable {
    public let selectedStrategy: StrategyKind
    public let confidence: Double
    public let rationale: String
    public let allowedOperatorFamilies: [OperatorFamily]
    public let candidateCountBeforeFiltering: Int
    public let candidateCountAfterFiltering: Int
    public let reevaluationCause: StrategyReevaluationCause?
    public let timestamp: Date

    public init(
        selectedStrategy: StrategyKind,
        confidence: Double,
        rationale: String,
        allowedOperatorFamilies: [OperatorFamily],
        candidateCountBeforeFiltering: Int = 0,
        candidateCountAfterFiltering: Int = 0,
        reevaluationCause: StrategyReevaluationCause? = nil,
        timestamp: Date = Date()
    ) {
        self.selectedStrategy = selectedStrategy
        self.confidence = confidence
        self.rationale = rationale
        self.allowedOperatorFamilies = allowedOperatorFamilies
        self.candidateCountBeforeFiltering = candidateCountBeforeFiltering
        self.candidateCountAfterFiltering = candidateCountAfterFiltering
        self.reevaluationCause = reevaluationCause
        self.timestamp = timestamp
    }

    /// Convert to a dictionary for JSON serialization.
    public func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "strategy": selectedStrategy.rawValue,
            "confidence": confidence,
            "rationale": rationale,
            "allowed_operator_families": allowedOperatorFamilies.map(\.rawValue),
            "candidate_count_before": candidateCountBeforeFiltering,
            "candidate_count_after": candidateCountAfterFiltering,
            "timestamp": ISO8601DateFormatter().string(from: timestamp),
        ]
        if let cause = reevaluationCause {
            dict["reevaluation_cause"] = cause.rawValue
        }
        return dict
    }
}

/// Accumulates strategy diagnostics entries and writes them to disk.
public final class StrategyDiagnosticsWriter: @unchecked Sendable {
    private let outputDirectory: URL
    private let lock = NSLock()
    private var entries: [StrategyDiagnostics] = []

    public init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    /// Record a strategy selection diagnostic entry.
    public func record(_ entry: StrategyDiagnostics) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(entry)
    }

    /// Create a diagnostic entry from a ``SelectedStrategy``.
    public func record(
        strategy: SelectedStrategy,
        candidateCountBefore: Int = 0,
        candidateCountAfter: Int = 0,
        reevaluationCause: StrategyReevaluationCause? = nil
    ) {
        let entry = StrategyDiagnostics(
            selectedStrategy: strategy.kind,
            confidence: strategy.confidence,
            rationale: strategy.rationale,
            allowedOperatorFamilies: strategy.allowedOperatorFamilies,
            candidateCountBeforeFiltering: candidateCountBefore,
            candidateCountAfterFiltering: candidateCountAfter,
            reevaluationCause: reevaluationCause
        )
        record(entry)
    }

    /// Returns recent diagnostics entries.
    public func recentEntries(limit: Int = 50) -> [StrategyDiagnostics] {
        lock.lock()
        defer { lock.unlock() }
        return Array(entries.suffix(limit))
    }

    /// Write all recorded entries to ``strategy_selection.jsonl``.
    public func flush() {
        lock.lock()
        let snapshot = entries
        lock.unlock()

        guard !snapshot.isEmpty else { return }

        do {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
            let url = outputDirectory.appendingPathComponent("strategy_selection.jsonl")
            let lines = snapshot.compactMap { entry -> String? in
                guard let data = try? JSONSerialization.data(
                    withJSONObject: entry.toDict(),
                    options: [.sortedKeys]
                ) else { return nil }
                return String(data: data, encoding: .utf8)
            }
            let content = lines.joined(separator: "\n") + "\n"
            if let data = content.data(using: .utf8) {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            // Diagnostics writing is best-effort; failures are non-fatal.
        }
    }
}
