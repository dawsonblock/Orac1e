// ResultSelector.swift — Chooses the best verified candidate result.
//
// After all candidates have been executed and verified, the selector
// picks the winner. Selection criteria (in priority order):
//   1. Prefer fully successful results over all others.
//   2. If no successful result exists, prefer partial successes over failures.
//   3. If only failures exist, choose among those.
//   4. Within the chosen group, highest score wins; ties are broken by lowest latency.

import Foundation

/// Selects the best ``CandidateResult`` from a set of executed candidates.
public struct ResultSelector: Sendable {
    public init() {}

    /// Choose the best result from the executed candidates.
    ///
    /// - Parameter results: All candidate results from this search cycle.
    /// - Returns: The single best result, or `nil` if no candidates were executed.
    public func selectBest(from results: [CandidateResult]) -> CandidateResult? {
        guard !results.isEmpty else { return nil }

        // Prefer fully successful results.
        let successful = results.filter { $0.success }
        if !successful.isEmpty {
            return successful.sorted(by: resultOrdering).first
        }

        // Fall back to partial successes over total failures.
        let partials = results.filter { $0.criticOutcome == .partialSuccess }
        if !partials.isEmpty {
            return partials.sorted(by: resultOrdering).first
        }

        // Last resort: return the highest-scored failure.
        return results.sorted(by: resultOrdering).first
    }

    /// Ordering: higher score first, then lower latency.
    private func resultOrdering(_ a: CandidateResult, _ b: CandidateResult) -> Bool {
        if a.score != b.score { return a.score > b.score }
        return a.elapsedMs < b.elapsedMs
    }
}
