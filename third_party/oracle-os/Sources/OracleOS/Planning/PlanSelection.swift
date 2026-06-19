import Foundation

public struct PlanSelection {
    public static func selectBest(
        familyDecision: PlannerDecision?,
        reasoningDecision: PlannerDecision?,
        taskGraphDecision: PlannerDecision? = nil,
        taskContext: TaskContext,
        worldState: WorldState,
        memoryStore: UnifiedMemoryStore
    ) -> PlannerDecision? {
        let memoryInfluence = MemoryRouter(memoryStore: memoryStore).influence(
            for: MemoryQueryContext(taskContext: taskContext, worldState: worldState)
        )
        let memoryBias = MemoryScorer.planBias(influence: memoryInfluence)

        let taskGraphScore = taskGraphDecision.map { decision -> Double in
            let baseScore = sourceConfidence(decision.source) + memoryBias
            return baseScore + 0.1
        }

        switch (familyDecision, reasoningDecision) {
        case let (family?, reasoning?):
            let familyScore = sourceConfidence(family.source) + memoryBias
            let reasoningScore = reasoning.planDiagnostics?.candidatePlans.first?.score ?? 0

            if family.source == reasoning.source,
               family.source == .workflow || family.source == .stableGraph {
                return family
            }

            if let tgScore = taskGraphScore, let tgDecision = taskGraphDecision,
               tgScore >= familyScore && tgScore >= reasoningScore {
                return tgDecision
            }

            if family.source == .workflow || family.source == .stableGraph {
                return familyScore >= reasoningScore ? family : reasoning
            }
            return reasoningScore > familyScore ? reasoning : family
        case let (family?, nil):
            if let tgScore = taskGraphScore, let tgDecision = taskGraphDecision {
                let familyScore = sourceConfidence(family.source) + memoryBias
                return tgScore >= familyScore ? tgDecision : family
            }
            return family
        case let (nil, reasoning?):
            if let tgScore = taskGraphScore, let tgDecision = taskGraphDecision {
                let reasoningScore = reasoning.planDiagnostics?.candidatePlans.first?.score ?? 0
                return tgScore >= reasoningScore ? tgDecision : reasoning
            }
            return reasoning
        case (nil, nil):
            return taskGraphDecision
        }
    }

    private static func sourceConfidence(_ source: PlannerSource) -> Double {
        switch source {
        case .workflow: return 0.9
        case .stableGraph: return 0.75
        case .candidateGraph: return 0.5
        case .exploration: return 0.3
        case .reasoning: return 0.6
        case .llm: return 0.45
        case .recovery: return 0.4
        case .strategy: return 0.95
        }
    }
}
