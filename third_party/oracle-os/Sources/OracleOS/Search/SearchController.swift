// SearchController.swift — Search-centric action selection.
//
// Replaces single-path action selection with candidate generation
// and verified selection. The runtime loop becomes:
//
//   state → generate candidates → execute → verify → select best
//
// The controller orchestrates the full search cycle and returns
// the single best verified result for the runtime to commit.

import Foundation

/// Orchestrates the search-centric action selection cycle.
///
/// Usage:
///
///     let controller = SearchController(generator: ..., selector: ...)
///     let best = controller.search(
///         compressedState: ...,
///         abstractState: ...,
///         evaluate: { candidate in ... }
///     )
@MainActor
public final class SearchController {
    private let generator: CandidateGenerator
    private let selector: ResultSelector

    public init(
        generator: CandidateGenerator,
        selector: ResultSelector = ResultSelector()
    ) {
        self.generator = generator
        self.selector = selector
    }

    /// Run a full search cycle: generate candidates, execute and verify
    /// each one, then select the best verified result.
    ///
    /// - Parameters:
    ///   - compressedState: Current compressed UI state from perception.
    ///   - abstractState: Current abstract task state for graph lookup.
    ///   - llmSchemas: Optional LLM fallback schemas.
    ///   - evaluate: Closure that executes a candidate and returns its
    ///     verified result. The caller is responsible for running the
    ///     candidate through ``VerifiedExecutor`` and ``CriticLoop``.
    /// - Returns: The best verified ``CandidateResult``, or `nil` if no
    ///   candidates could be generated or executed.
    public func search(
        compressedState: CompressedUIState,
        abstractState: AbstractTaskState,
        planningStateID: PlanningStateID,
        llmSchemas: [ActionSchema] = [],
        evaluate: (Candidate) -> CandidateResult?
    ) -> CandidateResult? {
        let candidates = generator.generate(
            compressedState: compressedState,
            abstractState: abstractState,
            planningStateID: planningStateID,
            llmSchemas: llmSchemas
        )

        guard !candidates.isEmpty else { return nil }

        var results: [CandidateResult] = []
        for candidate in candidates {
            if let result = evaluate(candidate) {
                results.append(result)
                // Early exit: if we find a fully successful result
                // from memory, prefer it immediately.
                if result.success && result.candidate.source == CandidateSource.memory {
                    break
                }
            }
        }

        return selector.selectBest(from: results)
    }

    /// Number of candidates the generator will produce per cycle.
    public var maxCandidates: Int { generator.maxCandidates }
}
