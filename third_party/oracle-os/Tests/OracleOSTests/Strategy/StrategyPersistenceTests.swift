import Foundation
import Testing
@testable import OracleOS

@Suite("Strategy Persistence")
struct StrategyPersistenceTests {

    @Test("Strategy evaluator records and tracks current strategy")
    func evaluatorTracksCurrentStrategy() {
        let evaluator = StrategyEvaluator()

        // Initially no active strategy
        #expect(evaluator.activeStrategy() == nil)

        let strategy = SelectedStrategy(
            kind: .repoRepair,
            confidence: 0.8,
            rationale: "test",
            allowedOperatorFamilies: [.repoAnalysis, .patchGeneration],
            reevaluateAfterStepCount: 3
        )
        evaluator.setCurrentStrategy(strategy)

        #expect(evaluator.activeStrategy()?.kind == .repoRepair)
        #expect(evaluator.stepsSinceStrategySelection() == 0)
    }

    @Test("Strategy evaluator increments step count")
    func evaluatorIncrementsSteps() {
        let evaluator = StrategyEvaluator()
        let strategy = SelectedStrategy(
            kind: .graphNavigation,
            confidence: 0.6,
            rationale: "test",
            allowedOperatorFamilies: [.graphEdge],
            reevaluateAfterStepCount: 5
        )
        evaluator.setCurrentStrategy(strategy)

        evaluator.recordStep()
        evaluator.recordStep()
        #expect(evaluator.stepsSinceStrategySelection() == 2)
    }

    @Test("Strategy evaluator triggers reevaluation at step threshold")
    func evaluatorReevaluatesAtThreshold() {
        let evaluator = StrategyEvaluator()
        let strategy = SelectedStrategy(
            kind: .repoRepair,
            confidence: 0.8,
            rationale: "test",
            allowedOperatorFamilies: [.repoAnalysis],
            reevaluateAfterStepCount: 2
        )
        evaluator.setCurrentStrategy(strategy)

        // Before threshold — no reevaluation needed
        evaluator.recordStep()
        #expect(evaluator.shouldReevaluate() == nil)

        // At threshold — should trigger
        evaluator.recordStep()
        let cause = evaluator.shouldReevaluate()
        #expect(cause == .stepThresholdReached)
    }

    @Test("Strategy evaluator triggers reevaluation on hard failure")
    func evaluatorReevaluatesOnFailure() {
        let evaluator = StrategyEvaluator()
        let strategy = SelectedStrategy(
            kind: .browserInteraction,
            confidence: 0.7,
            rationale: "test",
            allowedOperatorFamilies: [.browserTargeted]
        )
        evaluator.setCurrentStrategy(strategy)

        let cause = evaluator.shouldReevaluate(hardFailure: true)
        #expect(cause == .hardFailure)
    }

    @Test("Strategy evaluator triggers reevaluation when no strategy is active")
    func evaluatorReevaluatesWhenNoStrategy() {
        let evaluator = StrategyEvaluator()
        let cause = evaluator.shouldReevaluate()
        #expect(cause == .noActiveStrategy)
    }

    @Test("Strategy evaluator does not thrash on every step")
    func evaluatorDoesNotThrash() {
        let evaluator = StrategyEvaluator()
        let strategy = SelectedStrategy(
            kind: .workflowExecution,
            confidence: 0.9,
            rationale: "test",
            allowedOperatorFamilies: [.workflow],
            reevaluateAfterStepCount: 8
        )
        evaluator.setCurrentStrategy(strategy)

        // Steps 1-7 should not trigger reevaluation
        for _ in 1...7 {
            evaluator.recordStep()
            #expect(evaluator.shouldReevaluate() == nil)
        }

        // Step 8 should trigger
        evaluator.recordStep()
        #expect(evaluator.shouldReevaluate() == .stepThresholdReached)
    }

    @Test("StrategyReevaluationCause has all expected cases")
    func reevaluationCauseCases() {
        let causes: [StrategyReevaluationCause] = [
            .noActiveStrategy, .planCompleted, .hardFailure,
            .confidenceCollapsed, .taskNodeChanged, .stepThresholdReached,
        ]
        #expect(causes.count == 6)
    }
}
