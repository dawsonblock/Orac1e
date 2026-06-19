import Foundation

public struct RuntimeInspectorSnapshot: Sendable {
    public let chosenPlan: ScoredPlanSummary?
    public let rejectedPlans: [ScoredPlanSummary]
    public let memoryInfluences: [MemoryEvidence]
    public let notes: [String]

    public init(
        chosenPlan: ScoredPlanSummary? = nil,
        rejectedPlans: [ScoredPlanSummary] = [],
        memoryInfluences: [MemoryEvidence] = [],
        notes: [String] = []
    ) {
        self.chosenPlan = chosenPlan
        self.rejectedPlans = rejectedPlans
        self.memoryInfluences = memoryInfluences
        self.notes = notes
    }
}

public struct RuntimeInspector: Sendable {
    public init() {}

    public func inspect(
        decision: PlannerDecision?,
        memoryInfluence: MemoryInfluence
    ) -> RuntimeInspectorSnapshot {
        let chosenPlan = decision?.planDiagnostics?.candidatePlans.first
        let rejectedPlans = Array(decision?.planDiagnostics?.candidatePlans.dropFirst() ?? [])
        var notes: [String] = []

        if let source = decision?.source {
            notes.append("decision source: \(source.rawValue)")
        }
        if let fallback = decision?.fallbackReason {
            notes.append("fallback: \(fallback)")
        }
        notes.append(contentsOf: memoryInfluence.notes)

        return RuntimeInspectorSnapshot(
            chosenPlan: chosenPlan,
            rejectedPlans: rejectedPlans,
            memoryInfluences: memoryInfluence.evidence,
            notes: notes
        )
    }
}
