import Foundation
import Testing
@testable import OracleOS

@Suite("Patch Experiment Runner")
struct PatchExperimentRunnerTests {

    @Test("Experiment runner plans with applicable strategies")
    func runnerPlansWithStrategies() {
        let runner = PatchExperimentRunner()
        let plan = runner.plan(
            errorSignature: "Fatal error: Index out of range",
            faultLocationConfidence: 0.8,
            candidates: [makeCandidatePatch()],
            snapshot: nil
        )

        #expect(!plan.strategies.isEmpty)
        #expect(plan.faultLocationConfidence == 0.8)
        #expect(!plan.candidates.isEmpty)
    }

    @Test("Experiment plan captures error signature")
    func planCapturesErrorSignature() {
        let runner = PatchExperimentRunner()
        let plan = runner.plan(
            errorSignature: "nil unwrap",
            faultLocationConfidence: 0.6,
            candidates: [],
            snapshot: nil
        )

        #expect(plan.errorSignature == "nil unwrap")
    }

    @Test("Patch ranking signals compute composite score")
    func patchRankingSignalsComputeCompositeScore() {
        let signals = PatchRankingSignals(
            faultLocationConfidence: 0.9,
            patchComplexity: 0.2,
            coverageImpact: 0.7,
            memorySuccessPatterns: 0.5
        )

        #expect(signals.compositeScore > 0)
        // compositeScore = 0.4*0.9 + 0.25*(1-0.2) + 0.2*0.7 + 0.15*0.5
        let expected = 0.4 * 0.9 + 0.25 * 0.8 + 0.2 * 0.7 + 0.15 * 0.5
        #expect(abs(signals.compositeScore - expected) < 0.001)
    }

    private func makeCandidatePatch() -> CandidatePatch {
        CandidatePatch(
            id: "patch-1",
            title: "Fix boundary condition",
            summary: "Guard against out-of-bounds array access",
            workspaceRelativePath: "Sources/Calculator.swift",
            content: "+guard index < array.count else { return }"
        )
    }
}
