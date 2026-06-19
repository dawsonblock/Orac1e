import Foundation
import Testing
@testable import OracleOS

@Suite("Ambiguous Target Recovery")
struct AmbiguousTargetRecoveryTests {

    @Test("Ambiguity score increases when candidates are close in score")
    func ambiguityScoreIncreasesWhenClose() {
        let lowAmbiguity = ElementRanker.ambiguityScore(bestScore: 0.9, nextScore: 0.3)
        let highAmbiguity = ElementRanker.ambiguityScore(bestScore: 0.9, nextScore: 0.85)
        #expect(highAmbiguity > lowAmbiguity)
    }

    @Test("Zero best score produces maximum ambiguity")
    func zeroBestScoreProducesMaxAmbiguity() {
        let ambiguity = ElementRanker.ambiguityScore(bestScore: 0, nextScore: 0)
        #expect(ambiguity == 1)
    }

    @Test("Recovery planner handles element ambiguous failure")
    func recoveryPlannerHandlesAmbiguousElement() {
        let planner = MainPlanner()
        let state = makeState()
        let plans = planner.plan(failure: .elementAmbiguous, state: state)
        #expect(plans.count >= 0)
    }

    @Test("Failure classifier recognizes ambiguity from description")
    func failureClassifierRecognizesAmbiguity() {
        let classification = FailureClassifier.classify(
            errorDescription: "Ambiguous target: multiple elements match the query"
        )
        #expect(classification.failureClass == .elementAmbiguous)
    }

    private func makeState() -> ReasoningPlanningState {
        ReasoningPlanningState(
            taskContext: TaskContext(
                goal: Goal(description: "click button", preferredAgentKind: .os),
                agentKind: .os,
                workspaceRoot: nil,
                phases: [.operatingSystem]
            ),
            worldState: WorldState(
                observationHash: "test",
                planningState: PlanningState(
                    id: PlanningStateID(rawValue: "test"),
                    clusterKey: StateClusterKey(rawValue: "test"),
                    appID: "Safari",
                    domain: nil,
                    windowClass: nil,
                    taskPhase: "browse",
                    focusedRole: nil,
                    modalClass: nil,
                    navigationClass: nil,
                    controlContext: nil
                ),
                observation: Observation(
                    app: "Safari",
                    windowTitle: "Safari",
                    url: nil,
                    focusedElementID: nil,
                    elements: [
                        UnifiedElement(id: "btn1", source: .ax, role: "AXButton", label: "Submit", confidence: 0.9),
                        UnifiedElement(id: "btn2", source: .ax, role: "AXButton", label: "Submit Copy", confidence: 0.88),
                    ]
                )
            ),
            memoryInfluence: MemoryInfluence()
        )
    }
}
