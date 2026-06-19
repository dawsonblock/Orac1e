import Foundation

public final class WorkflowIndex: @unchecked Sendable {
    private var plans: [String: WorkflowPlan]
    private let decayPolicy: WorkflowDecayPolicy

    public init(
        plans: [String: WorkflowPlan] = [:],
        decayPolicy: WorkflowDecayPolicy = WorkflowDecayPolicy()
    ) {
        self.plans = plans
        self.decayPolicy = decayPolicy
    }

    public func add(_ plan: WorkflowPlan) {
        plans[plan.id] = plan
    }

    public func remove(id: String) {
        plans.removeValue(forKey: id)
    }

    public func allPlans() -> [WorkflowPlan] {
        plans.values.sorted { lhs, rhs in
            if lhs.successRate == rhs.successRate {
                return lhs.goalPattern < rhs.goalPattern
            }
            return lhs.successRate > rhs.successRate
        }
    }

    public func promotedPlans(for agentKind: AgentKind? = nil) -> [WorkflowPlan] {
        allPlans().filter { plan in
            plan.promotionStatus == .promoted
                && !decayPolicy.isStale(plan)
                && (
                agentKind == nil
                    || agentKind == .mixed
                    || plan.agentKind == agentKind
            )
        }
    }

    /// Returns promoted workflows whose goal pattern matches the given goal.
    public func matching(goal: Goal) -> [WorkflowPlan] {
        let goalLower = goal.description.lowercased()
        return promotedPlans(for: goal.preferredAgentKind).filter { plan in
            let patternLower = plan.goalPattern.lowercased()
            return goalLower.contains(patternLower) || patternLower.contains(goalLower)
        }
    }
}
