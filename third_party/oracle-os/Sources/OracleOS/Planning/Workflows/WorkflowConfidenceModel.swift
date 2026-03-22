import Foundation

public struct WorkflowConfidence: Sendable {
    public let score: Double
    public let successRate: Double
    public let executionCount: Int
    public let lastSuccessAge: TimeInterval?
    public let driftRate: Double
    public let notes: [String]

    public init(
        score: Double,
        successRate: Double,
        executionCount: Int,
        lastSuccessAge: TimeInterval? = nil,
        driftRate: Double = 0,
        notes: [String] = []
    ) {
        self.score = score
        self.successRate = successRate
        self.executionCount = executionCount
        self.lastSuccessAge = lastSuccessAge
        self.driftRate = driftRate
        self.notes = notes
    }

    public func isReliable(threshold: Double = 0.5) -> Bool {
        score >= threshold
    }
}

public struct WorkflowConfidenceModel: Sendable {
    public let successRateWeight: Double
    public let executionCountWeight: Double
    public let recencyWeight: Double
    public let replayValidationWeight: Double
    public let driftPenaltyWeight: Double

    public init(
        successRateWeight: Double = 0.35,
        executionCountWeight: Double = 0.20,
        recencyWeight: Double = 0.20,
        replayValidationWeight: Double = 0.15,
        driftPenaltyWeight: Double = 0.10
    ) {
        self.successRateWeight = successRateWeight
        self.executionCountWeight = executionCountWeight
        self.recencyWeight = recencyWeight
        self.replayValidationWeight = replayValidationWeight
        self.driftPenaltyWeight = driftPenaltyWeight
    }

    /// Compute confidence with an optional strategy boost.
    ///
    /// When a workflow repeatedly succeeds inside the same strategy, its
    /// confidence is boosted. Low-ambiguity replays within the strategy
    /// also increase the score.
    public func confidence(
        for workflow: WorkflowPlan,
        selectedStrategy: SelectedStrategy? = nil
    ) -> WorkflowConfidence {
        var notes: [String] = []

        let successComponent = workflow.successRate * successRateWeight
        notes.append("success rate \(String(format: "%.2f", workflow.successRate))")

        let countNormalized = min(Double(workflow.repeatedTraceSegmentCount) / 10.0, 1.0)
        let countComponent = countNormalized * executionCountWeight
        notes.append("execution count \(workflow.repeatedTraceSegmentCount)")

        let recencyComponent: Double
        let lastSuccessAge: TimeInterval?
        if let lastSuccess = workflow.lastSucceededAt {
            let age = Date().timeIntervalSince(lastSuccess)
            lastSuccessAge = age
            let ageDays = age / 86400
            let recencyScore = max(0, 1.0 - (ageDays / 30.0))
            recencyComponent = recencyScore * recencyWeight
            notes.append("last success \(String(format: "%.1f", ageDays)) days ago")
        } else {
            lastSuccessAge = nil
            recencyComponent = 0
        }

        let replayComponent = workflow.replayValidationSuccess * replayValidationWeight
        notes.append("replay validation \(String(format: "%.2f", workflow.replayValidationSuccess))")

        let driftRate = Self.computeDriftRate(workflow)
        let driftPenalty = driftRate * driftPenaltyWeight
        if driftRate > 0 {
            notes.append("drift rate \(String(format: "%.2f", driftRate))")
        }

        var totalScore = successComponent + countComponent + recencyComponent + replayComponent - driftPenalty

        // ── Strategy boost: reward workflows that align with the active strategy ──
        if let strategy = selectedStrategy {
            let strategyBoost = strategyAlignmentBoost(workflow: workflow, strategy: strategy, notes: &notes)
            totalScore += strategyBoost
        }

        return WorkflowConfidence(
            score: min(max(totalScore, 0), 1.0),
            successRate: workflow.successRate,
            executionCount: workflow.repeatedTraceSegmentCount,
            lastSuccessAge: lastSuccessAge,
            driftRate: driftRate,
            notes: notes
        )
    }

    public func isReliable(_ workflow: WorkflowPlan, threshold: Double = 0.5) -> Bool {
        confidence(for: workflow).score >= threshold
    }

    public func score(plan: WorkflowPlan) -> WorkflowConfidence {
        confidence(for: plan)
    }

    /// Strategy alignment boost for workflows that match the current strategy.
    private func strategyAlignmentBoost(
        workflow: WorkflowPlan,
        strategy: SelectedStrategy,
        notes: inout [String]
    ) -> Double {
        let skills = workflow.steps.map { $0.actionContract.skillName.lowercased() }
        let families = Set(skills.map { LedgerNavigator.operatorFamilyForAction($0) })
        let allowed = Set(strategy.allowedOperatorFamilies)

        // Fraction of workflow families that are strategy-allowed.
        guard !families.isEmpty else { return 0 }
        let alignedCount = families.filter { allowed.contains($0) }.count
        let alignment = Double(alignedCount) / Double(families.count)

        if alignment >= 0.8 {
            notes.append("strategy-aligned workflow (alignment: \(String(format: "%.0f%%", alignment * 100)))")
            return 0.08
        } else if alignment >= 0.5 {
            return 0.03
        }
        return 0
    }

    private static func computeDriftRate(_ workflow: WorkflowPlan) -> Double {
        guard workflow.repeatedTraceSegmentCount > 1 else { return 0 }
        let replayDrift = max(0, 1.0 - workflow.replayValidationSuccess)
        let successDrift = max(0, 1.0 - workflow.successRate)
        return (replayDrift + successDrift) / 2.0
    }
}
