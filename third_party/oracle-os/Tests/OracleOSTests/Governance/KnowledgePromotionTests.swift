import Foundation
import Testing
@testable import OracleOS

@Suite("Knowledge Promotion")
struct KnowledgePromotionTests {

    @Test("Graph edges require multiple observations before promotion")
    func graphEdgesRequireMultipleObservations() {
        let policy = GraphPromotionPolicy()
        let edge = makeEdge(attempts: 1, successes: 1, lastSuccessTimestamp: Date().timeIntervalSince1970)
        #expect(!policy.shouldPromote(edge: edge, now: Date()))
    }

    @Test("Graph edges with enough attempts and high success can promote")
    func graphEdgesWithEnoughAttemptsCanPromote() {
        let policy = GraphPromotionPolicy()
        let edge = makeEdge(
            attempts: 5,
            successes: 5,
            lastSuccessTimestamp: Date().timeIntervalSince1970
        )
        #expect(policy.shouldPromote(edge: edge, now: Date()))
    }

    @Test("Graph edges with low success rate do not promote")
    func graphEdgesWithLowSuccessDoNotPromote() {
        let policy = GraphPromotionPolicy()
        let edge = makeEdge(
            attempts: 10,
            successes: 3,
            lastSuccessTimestamp: Date().timeIntervalSince1970
        )
        #expect(!policy.shouldPromote(edge: edge, now: Date()))
    }

    @Test("Workflows require repeated validated success for promotion")
    func workflowsRequireRepeatedSuccess() {
        let policy = WorkflowPromotionPolicy()
        let plan = makeWorkflowPlan(
            successRate: 1.0,
            segmentCount: 1,
            replayValidation: 1.0,
            sourceTraceRefs: ["session1:task1:0"]
        )
        #expect(!policy.shouldPromote(plan))
    }

    @Test("Workflows with sufficient evidence can promote")
    func workflowsWithSufficientEvidenceCanPromote() {
        let policy = WorkflowPromotionPolicy()
        let plan = makeWorkflowPlan(
            successRate: 0.9,
            segmentCount: 4,
            replayValidation: 0.8,
            sourceTraceRefs: ["session1:task1:0", "session2:task2:0", "session3:task3:0"]
        )
        #expect(policy.shouldPromote(plan))
    }

    @Test("Memory decay policy reduces stale patterns")
    func memoryDecayPolicyReducesStalePatterns() {
        let now = Date()
        let recentScore = MemoryDecayPolicy.freshnessMultiplier(since: now, now: now)
        let oldDate = now.addingTimeInterval(-(60 * 60 * 24 * 60))
        let oldScore = MemoryDecayPolicy.freshnessMultiplier(since: oldDate, now: now)
        #expect(recentScore >= oldScore)
    }

    @Test("Workflow confidence model penalizes low replay validation")
    func confidenceModelPenalizesLowReplay() {
        let model = WorkflowConfidenceModel()
        let validated = model.confidence(for: makeWorkflowPlan(
            successRate: 0.8,
            segmentCount: 3,
            replayValidation: 1.0,
            sourceTraceRefs: ["s1:t1:0", "s2:t2:0"]
        ))
        let unvalidated = model.confidence(for: makeWorkflowPlan(
            successRate: 0.8,
            segmentCount: 3,
            replayValidation: 0.0,
            sourceTraceRefs: ["s1:t1:0", "s2:t2:0"]
        ))
        #expect(validated.score > unvalidated.score)
    }

    @Test("Workflow confidence model penalizes high drift rate")
    func confidenceModelPenalizesHighDrift() {
        let model = WorkflowConfidenceModel()
        let stable = model.confidence(for: makeWorkflowPlan(
            successRate: 0.9,
            segmentCount: 5,
            replayValidation: 0.9,
            sourceTraceRefs: ["s1:t1:0", "s2:t2:0", "s3:t3:0"]
        ))
        let drifting = model.confidence(for: makeWorkflowPlan(
            successRate: 0.4,
            segmentCount: 5,
            replayValidation: 0.3,
            sourceTraceRefs: ["s1:t1:0", "s2:t2:0", "s3:t3:0"]
        ))
        #expect(stable.score > drifting.score)
        #expect(stable.driftRate < drifting.driftRate)
    }

    @Test("One-off traces do not get promoted to workflows")
    func oneOffTracesDoNotPromote() {
        let policy = WorkflowPromotionPolicy()
        let singleEpisodePlan = makeWorkflowPlan(
            successRate: 1.0,
            segmentCount: 1,
            replayValidation: 1.0,
            sourceTraceRefs: ["session1:task1:0"]
        )
        #expect(!policy.shouldPromote(singleEpisodePlan))
    }

    @Test("Sparse evidence does not promote workflows")
    func sparseEvidenceDoesNotPromote() {
        let policy = WorkflowPromotionPolicy()
        // 2 attempts, both successful, but only 2 segments — below threshold
        let plan = makeWorkflowPlan(
            successRate: 1.0,
            segmentCount: 2,
            replayValidation: 1.0,
            sourceTraceRefs: ["s1:t1:0", "s2:t2:0"]
        )
        #expect(!policy.shouldPromote(plan), "Sparse evidence (only 2 segments) should not promote")
    }

    @Test("Workflows require distinct episodes for promotion")
    func workflowsRequireDistinctEpisodes() {
        let policy = WorkflowPromotionPolicy()
        let sameEpisodePlan = makeWorkflowPlan(
            successRate: 1.0,
            segmentCount: 5,
            replayValidation: 1.0,
            sourceTraceRefs: ["session1:task1:0", "session1:task1:1", "session1:task1:2"]
        )
        #expect(!policy.shouldPromote(sameEpisodePlan))
    }

    private func makeEdge(
        attempts: Int = 1,
        successes: Int? = nil,
        ambiguityTotal: Double = 0,
        lastSuccessTimestamp: Double? = nil,
        recentOutcomes: [Bool] = [],
        recoveryTagged: Bool = false,
        knowledgeTier: KnowledgeTier = .candidate
    ) -> EdgeTransition {
        EdgeTransition(
            edgeID: UUID().uuidString,
            fromPlanningStateID: PlanningStateID(rawValue: "state-a"),
            toPlanningStateID: PlanningStateID(rawValue: "state-b"),
            actionContractID: "click|AXButton|OK|query",
            postconditionClass: .elementAppeared,
            attempts: attempts,
            successes: successes ?? attempts,
            lastSuccessTimestamp: lastSuccessTimestamp,
            recentOutcomes: recentOutcomes,
            ambiguityTotal: ambiguityTotal,
            recoveryTagged: recoveryTagged,
            knowledgeTier: knowledgeTier
        )
    }

    private func makeWorkflowPlan(
        successRate: Double,
        segmentCount: Int,
        replayValidation: Double = 1.0,
        sourceTraceRefs: [String] = []
    ) -> WorkflowPlan {
        WorkflowPlan(
            agentKind: .os,
            goalPattern: "test promotion",
            steps: [
                WorkflowStep(
                    agentKind: .os,
                    stepPhase: .operatingSystem,
                    actionContract: ActionContract(
                        id: "click|AXButton|OK|query",
                        skillName: "click",
                        targetRole: "AXButton",
                        targetLabel: "OK",
                        locatorStrategy: "query"
                    )
                ),
            ],
            successRate: successRate,
            sourceTraceRefs: sourceTraceRefs,
            evidenceTiers: [.candidate],
            repeatedTraceSegmentCount: segmentCount,
            replayValidationSuccess: replayValidation,
            promotionStatus: .candidate
        )
    }
}
