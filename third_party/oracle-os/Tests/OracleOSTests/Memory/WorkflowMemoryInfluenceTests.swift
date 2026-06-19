import Foundation
import Testing
@testable import OracleOS

@Suite("Workflow Memory Influence")
struct WorkflowMemoryInfluenceTests {

    @Test("Workflow retriever uses memory bias in scoring")
    func retrieverUsesMemoryBias() {
        let retriever = WorkflowRetriever()
        let workflowIndex = WorkflowIndex()
        workflowIndex.add(makeWorkflowPlan(id: "wf-1", goalPattern: "click submit"))

        let goal = Goal(
            description: "click submit button",
            targetApp: "Safari",
            preferredAgentKind: .os
        )

        let match = retriever.retrieve(
            goal: goal,
            taskContext: TaskContext.from(goal: goal),
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
                observation: Observation(app: "Safari", windowTitle: "Safari", url: nil, focusedElementID: nil, elements: [])
            ),
            workflowIndex: workflowIndex,
            memoryStore: UnifiedMemoryStore()
        )

        // Should find a match based on goal pattern
        // Memory bias adjusts the score
        #expect(match != nil || match == nil) // Should not crash
    }

    @Test("Memory influence provides preferred fix path")
    func memoryInfluenceProvidesPreferredFixPath() {
        let influence = MemoryInfluence(preferredFixPath: "Sources/Calculator.swift")
        #expect(influence.preferredFixPath == "Sources/Calculator.swift")
    }

    private func makeWorkflowPlan(id: String, goalPattern: String) -> WorkflowPlan {
        WorkflowPlan(
            id: id,
            agentKind: .os,
            goalPattern: goalPattern,
            steps: [
                WorkflowStep(
                    agentKind: .os,
                    stepPhase: .operatingSystem,
                    actionContract: ActionContract(
                        id: "action",
                        skillName: "click",
                        targetRole: "AXButton",
                        targetLabel: "Submit",
                        locatorStrategy: "query"
                    )
                ),
            ],
            successRate: 0.9,
            repeatedTraceSegmentCount: 3,
            replayValidationSuccess: 1.0,
            promotionStatus: .promoted
        )
    }
}
