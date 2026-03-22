import Foundation
import Testing
@testable import OracleOS

@Suite("Workflow Confidence")
struct WorkflowConfidenceTests {

    @Test("Workflow confidence model scores based on success rate")
    func confidenceModelScoresSuccessRate() {
        let model = WorkflowConfidenceModel()
        let highSuccessPlan = makeWorkflowPlan(successRate: 0.95, replayValidation: 1.0)
        let lowSuccessPlan = makeWorkflowPlan(successRate: 0.3, replayValidation: 0.5)

        let highConfidence = model.score(plan: highSuccessPlan)
        let lowConfidence = model.score(plan: lowSuccessPlan)

        #expect(highConfidence.score > lowConfidence.score)
    }

    @Test("Workflow confidence isReliable uses threshold")
    func confidenceIsReliableUsesThreshold() {
        let model = WorkflowConfidenceModel()
        let reliablePlan = makeWorkflowPlan(successRate: 0.95, replayValidation: 1.0)
        let unreliablePlan = makeWorkflowPlan(successRate: 0.1, replayValidation: 0.0)

        let reliableConfidence = model.score(plan: reliablePlan)
        let unreliableConfidence = model.score(plan: unreliablePlan)

        #expect(reliableConfidence.isReliable())
        #expect(!unreliableConfidence.isReliable())
    }

    @Test("Replay validation influences confidence score")
    func replayValidationInfluencesConfidence() {
        let model = WorkflowConfidenceModel()
        let validatedPlan = makeWorkflowPlan(successRate: 0.8, replayValidation: 1.0)
        let unvalidatedPlan = makeWorkflowPlan(successRate: 0.8, replayValidation: 0.0)

        let validatedConfidence = model.score(plan: validatedPlan)
        let unvalidatedConfidence = model.score(plan: unvalidatedPlan)

        #expect(validatedConfidence.score > unvalidatedConfidence.score)
    }

    private func makeWorkflowPlan(
        successRate: Double,
        replayValidation: Double
    ) -> WorkflowPlan {
        WorkflowPlan(
            id: UUID().uuidString,
            agentKind: .os,
            goalPattern: "test workflow",
            steps: [
                WorkflowStep(
                    agentKind: .os,
                    stepPhase: .operatingSystem,
                    actionContract: ActionContract(
                        id: "test-action",
                        skillName: "click",
                        targetRole: "AXButton",
                        targetLabel: "OK",
                        locatorStrategy: "query"
                    )
                ),
            ],
            successRate: successRate,
            repeatedTraceSegmentCount: 3,
            replayValidationSuccess: replayValidation,
            promotionStatus: .candidate
        )
    }
}
