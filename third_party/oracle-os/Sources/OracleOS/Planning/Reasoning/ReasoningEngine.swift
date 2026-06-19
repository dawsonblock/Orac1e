import Foundation

public final class ReasoningEngine: @unchecked Sendable {
    public let maxDepth: Int
    public let maxPlans: Int
    private let operatorRegistry: OperatorRegistry

    public init(
        maxDepth: Int = 3,
        maxPlans: Int = 5,
        operatorRegistry: OperatorRegistry = .shared
    ) {
        self.maxDepth = maxDepth
        self.maxPlans = maxPlans
        self.operatorRegistry = operatorRegistry
    }

    public func generatePlans(from state: ReasoningPlanningState) -> [PlanCandidate] {
        var plans: [PlanCandidate] = []
        var seen: Set<[ReasoningOperatorKind]> = []
        expand(
            state: state,
            current: [],
            depth: 0,
            plans: &plans,
            seen: &seen
        )
        return plans
    }

    private func expand(
        state: ReasoningPlanningState,
        current: [Operator],
        depth: Int,
        plans: inout [PlanCandidate],
        seen: inout Set<[ReasoningOperatorKind]>
    ) {
        guard plans.count < maxPlans else { return }

        if !current.isEmpty {
            let kinds = current.map(\.kind)
            if seen.insert(kinds).inserted {
                plans.append(PlanCandidate(operators: current, projectedState: state))
            }
        }

        guard depth < maxDepth else { return }

        let available = operatorRegistry.available(for: state)
        for op in available {
            if current.last?.kind == op.kind {
                continue
            }

            let newState = op.effect(state)
            guard newState != state else {
                continue
            }

            expand(
                state: newState,
                current: current + [op],
                depth: depth + 1,
                plans: &plans,
                seen: &seen
            )

            if plans.count >= maxPlans {
                return
            }
        }
    }
}
