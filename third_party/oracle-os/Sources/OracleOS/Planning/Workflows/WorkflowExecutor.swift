import Foundation

public struct WorkflowExecutor: Sendable {
    public init() {}

    public func nextDecision(
        match: WorkflowMatch,
        plannerFamily: PlannerFamily,
        sourceNotes: [String] = []
    ) -> PlannerDecision {
        let step = match.plan.steps[match.stepIndex]
        return PlannerDecision(
            agentKind: step.agentKind,
            skillName: step.actionContract.skillName,
            plannerFamily: plannerFamily,
            stepPhase: step.stepPhase,
            actionContract: step.actionContract,
            source: .workflow,
            workflowID: match.plan.id,
            workflowStepID: step.id,
            fallbackReason: nil,
            semanticQuery: step.semanticQuery,
            projectMemoryRefs: match.projectMemoryRefs,
            notes: ["workflow \(match.plan.goalPattern)"] + sourceNotes + step.notes
        )
    }
}
