import Foundation

public struct ExperimentResultRanker: Sendable {
    private let patchRanker: PatchRanker

    public init(patchRanker: PatchRanker = PatchRanker()) {
        self.patchRanker = patchRanker
    }

    public func rank(
        results: [ExperimentResult],
        faultLocationConfidence: Double = 0,
        memorySuccessPatterns: Double = 0
    ) -> [ExperimentResult] {
        let signals = results.reduce(into: [Candidate.ID: PatchRankingSignals]()) { dict, result in
            dict[result.candidate.id] = PatchRankingSignals(
                faultLocationConfidence: faultLocationConfidence,
                patchComplexity: patchComplexity(result),
                coverageImpact: coverageImpact(result),
                memorySuccessPatterns: memorySuccessPatterns
            )
        }


        return patchRanker.rankWithSignals(results, signals: signals)
    }

    public func bestResult(
        _ results: [ExperimentResult],
        faultLocationConfidence: Double = 0,
        memorySuccessPatterns: Double = 0
    ) -> ExperimentResult? {
        rank(
            results: results,
            faultLocationConfidence: faultLocationConfidence,
            memorySuccessPatterns: memorySuccessPatterns
        ).first
    }

    private func patchComplexity(_ result: ExperimentResult) -> Double {
        let lineCount = Double(result.diffSummary.components(separatedBy: "\n").count)
        return min(lineCount / 100.0, 1.0)
    }

    private func coverageImpact(_ result: ExperimentResult) -> Double {
        result.succeeded ? 0.8 : 0.0
    }
}
