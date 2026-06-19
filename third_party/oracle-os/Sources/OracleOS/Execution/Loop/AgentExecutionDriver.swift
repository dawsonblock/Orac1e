import Foundation

@MainActor
public protocol AgentExecutionDriver {
    func execute(
        intent: ActionIntent,
        plannerDecision: PlannerDecision,
        selectedCandidate: ElementCandidate?
    ) -> ToolResult
}
