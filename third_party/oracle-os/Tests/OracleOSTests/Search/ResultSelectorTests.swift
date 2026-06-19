import Foundation
import Testing
@testable import OracleOS

@Suite("Search — ResultSelector")
struct ResultSelectorTests {
    let selector = ResultSelector()

    @Test("selectBest returns nil for empty results")
    func emptyResultsReturnsNil() {
        #expect(selector.selectBest(from: []) == nil)
    }

    @Test("selectBest prefers successful result over failure")
    func prefersSuccessOverFailure() {
        let success = makeResult(success: true, score: 0.8, outcome: .success)
        let failure = makeResult(success: false, score: 0.9, outcome: .failure)
        let best = selector.selectBest(from: [failure, success])
        #expect(best?.success == true)
    }

    @Test("selectBest prefers higher score among successes")
    func prefersHigherScoreAmongSuccesses() {
        let low = makeResult(success: true, score: 0.5, outcome: .success, name: "low")
        let high = makeResult(success: true, score: 0.9, outcome: .success, name: "high")
        let best = selector.selectBest(from: [low, high])
        #expect(best?.candidate.schema.name == "high")
    }

    @Test("selectBest breaks ties by lower latency")
    func breaksTiesByLatency() {
        let slow = makeResult(success: true, score: 0.9, outcome: .success, latencyMs: 500, name: "slow")
        let fast = makeResult(success: true, score: 0.9, outcome: .success, latencyMs: 100, name: "fast")
        let best = selector.selectBest(from: [slow, fast])
        #expect(best?.candidate.schema.name == "fast")
    }

    @Test("selectBest falls back to partial success when no full success")
    func fallsBackToPartialSuccess() {
        let partial = makeResult(success: false, score: 0.5, outcome: .partialSuccess)
        let failure = makeResult(success: false, score: 0.3, outcome: .failure)
        let best = selector.selectBest(from: [failure, partial])
        #expect(best?.criticOutcome == .partialSuccess)
    }

    @Test("selectBest returns highest-scored failure as last resort")
    func lastResortFailure() {
        let f1 = makeResult(success: false, score: 0.1, outcome: .failure, name: "f1")
        let f2 = makeResult(success: false, score: 0.3, outcome: .failure, name: "f2")
        let best = selector.selectBest(from: [f1, f2])
        #expect(best?.candidate.schema.name == "f2")
    }

    // MARK: - Helpers

    private func makeResult(
        success: Bool,
        score: Double,
        outcome: CriticOutcome,
        latencyMs: Double = 0,
        name: String = "test"
    ) -> CandidateResult {
        CandidateResult(
            candidate: Candidate(
                hypothesis: "h",
                schema: ActionSchema(name: name, kind: .click),
                source: .memory
            ),
            success: success,
            score: score,
            criticOutcome: outcome,
            elapsedMs: latencyMs
        )
    }
}
