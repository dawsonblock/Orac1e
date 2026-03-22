import Foundation

public final class ExplorationPolicy: @unchecked Sendable {
    public init() {}

    public func choose(
        goal: Goal,
        worldState: WorldState
    ) -> PlannerDecision? {
        if let targetApp = goal.targetApp,
           worldState.observation.app != targetApp {
            let contract = ActionContract(
                id: "explore|focus|\(targetApp)",
                skillName: "focus",
                targetRole: nil,
                targetLabel: targetApp,
                locatorStrategy: "exploration-focus"
            )
            return PlannerDecision(
                actionContract: contract,
                source: .exploration,
                fallbackReason: "trusted workflow and graph knowledge are unavailable",
                notes: ["focus target app before graph reuse"]
            )
        }

        let queryText = explorationLabel(goal: goal, worldState: worldState)
        let query = ElementQuery(
            text: queryText,
            role: nil,
            editable: false,
            clickable: true,
            visibleOnly: true,
            app: goal.targetApp ?? worldState.observation.app
        )
        let contract = ActionContract(
            id: "explore|click|\(worldState.planningState.appID)|\(queryText)",
            skillName: "click",
            targetRole: nil,
            targetLabel: queryText,
            locatorStrategy: "exploration"
        )
        return PlannerDecision(
            actionContract: contract,
            source: .exploration,
            fallbackReason: "trusted workflow and graph knowledge are unavailable",
            semanticQuery: query,
            notes: ["bounded exploration fallback"]
        )
    }

    private func explorationLabel(goal: Goal, worldState: WorldState) -> String {
        let lowercased = goal.description.lowercased()
        if lowercased.contains("compose") {
            return "Compose"
        }
        if lowercased.contains("send") {
            return "Send"
        }
        if lowercased.contains("rename") {
            return "Rename"
        }
        if lowercased.contains("save") {
            return "Save"
        }
        return worldState.planningState.controlContext
            ?? worldState.planningState.windowClass
            ?? goal.targetTaskPhase
            ?? goal.targetDomain
            ?? "Continue"
    }
}
