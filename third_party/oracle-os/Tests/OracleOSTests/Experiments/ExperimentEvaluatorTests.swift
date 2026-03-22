import Testing
import Foundation
@testable import OracleOS

@Suite("Experiment Evaluator")
struct ExperimentEvaluatorTests {

    // MARK: - Helpers

    private func makeOutcome(
        actions: [(String, Bool, Bool, Int)] = [],
        postconditionsPassed: Int = 0,
        postconditionsTotal: Int = 0
    ) -> TaskOutcome {
        TaskOutcome(
            taskID: "test-task",
            goalDescription: "unit test",
            actionResults: actions.map {
                ActionOutcomeSummary(actionName: $0.0, success: $0.1, verified: $0.2, durationMs: $0.3)
            },
            elapsedMs: actions.map(\.3).reduce(0, +),
            artifactCount: 0,
            postconditionsPassed: postconditionsPassed,
            postconditionsTotal: postconditionsTotal
        )
    }

    // MARK: - Score Range

    @Test("Perfect outcome scores close to 1.0")
    func perfectScore() {
        let outcome = makeOutcome(
            actions: [("click", true, true, 100), ("type", true, true, 50)],
            postconditionsPassed: 2,
            postconditionsTotal: 2
        )
        let evaluator = ExperimentEvaluator()
        let score = evaluator.evaluate(outcome)
        #expect(score.overall > 0.9)
        #expect(score.dimensions["correctness"]! == 1.0)
        #expect(score.dimensions["completion"]! == 1.0)
    }

    @Test("Complete failure scores close to 0.0")
    func failedScore() {
        let outcome = makeOutcome(
            actions: [("click", false, false, 6000)],
            postconditionsPassed: 0,
            postconditionsTotal: 3
        )
        let evaluator = ExperimentEvaluator()
        let score = evaluator.evaluate(outcome)
        #expect(score.overall < 0.15)
        #expect(score.dimensions["correctness"]! == 0.0)
    }

    @Test("Score is clamped between 0 and 1")
    func scoreClamped() {
        let outcome = makeOutcome(
            actions: [("click", true, true, 0)],
            postconditionsPassed: 1,
            postconditionsTotal: 1
        )
        let evaluator = ExperimentEvaluator()
        let score = evaluator.evaluate(outcome)
        #expect(score.overall >= 0.0)
        #expect(score.overall <= 1.0)
    }

    // MARK: - Weighted Dimensions

    @Test("Custom weights affect overall score")
    func customWeights() {
        let outcome = makeOutcome(
            actions: [("click", true, false, 100)],
            postconditionsPassed: 0,
            postconditionsTotal: 1
        )
        // Weight correctness at 1.0, everything else at 0.
        let heavy = ExperimentEvaluator(
            weights: .init(correctness: 1.0, efficiency: 0, verification: 0, completion: 0)
        )
        let score = heavy.evaluate(outcome)
        #expect(score.overall == 0.0) // postconditions 0/1

        let light = ExperimentEvaluator(
            weights: .init(correctness: 0, efficiency: 0, verification: 0, completion: 1.0)
        )
        let score2 = light.evaluate(outcome)
        #expect(score2.overall == 1.0) // completion 1/1
    }

    // MARK: - Explanation

    @Test("Explanation contains dimension names")
    func explanationContent() {
        let outcome = makeOutcome(actions: [("a", true, true, 100)])
        let score = ExperimentEvaluator().evaluate(outcome)
        #expect(score.explanation.contains("correctness"))
        #expect(score.explanation.contains("completion"))
    }
}
