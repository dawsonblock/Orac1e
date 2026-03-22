import Foundation

public struct MemoryDecisionBias: Sendable {
    public let successPatternBias: Double
    public let failurePatternPenalty: Double
    public let projectSpecificBias: Double
    public let recentTraceBias: Double
    public let totalBias: Double
    public let notes: [String]

    public init(
        successPatternBias: Double = 0,
        failurePatternPenalty: Double = 0,
        projectSpecificBias: Double = 0,
        recentTraceBias: Double = 0,
        notes: [String] = []
    ) {
        self.successPatternBias = successPatternBias
        self.failurePatternPenalty = failurePatternPenalty
        self.projectSpecificBias = projectSpecificBias
        self.recentTraceBias = recentTraceBias
        self.totalBias = successPatternBias - failurePatternPenalty + projectSpecificBias + recentTraceBias
        self.notes = notes
    }
}

public final class MemoryDecisionBiasCalculator: @unchecked Sendable {
    private let memoryRouter: MemoryRouter

public init(memoryStore: UnifiedMemoryStore) {
        self.memoryRouter = MemoryRouter(memoryStore: memoryStore)
    }

    /// Compute memory bias for a plan, optionally scoped by strategy.
    ///
    /// When a ``SelectedStrategy`` is provided, bias values are adjusted
    /// to prefer patterns that succeeded within the same strategy kind.
    public func bias(
        plan: PlanCandidate,
        goal: Goal,
        worldState: WorldState,
        taskContext: TaskContext,
        selectedStrategy: SelectedStrategy
    ) -> MemoryDecisionBias {
        guard let firstOperator = plan.operators.first else {
            return MemoryDecisionBias()
        }

        let memoryInfluence = memoryRouter.influence(
            for: MemoryQueryContext(
                taskContext: taskContext,
                worldState: worldState,
                errorSignature: goal.description
            )
        )

        var notes: [String] = []

        var successBias = memoryInfluence.executionRankingBias
        if successBias > 0 {
            notes.append("successful pattern bias \(String(format: "%.2f", successBias))")
        }

        let failurePenalty = memoryInfluence.riskPenalty
        if failurePenalty > 0 {
            notes.append("failure pattern penalty \(String(format: "%.2f", failurePenalty))")
        }

        let projectBias = memoryInfluence.projectMemorySignals.refs.isEmpty ? 0.0 : min(Double(memoryInfluence.projectMemorySignals.refs.count) * 0.03, 0.15)
        if projectBias > 0 {
            notes.append("project-specific bias \(String(format: "%.2f", projectBias))")
        }

        let commandBias = memoryInfluence.commandBias
        if commandBias > 0 {
            notes.append("recent trace bias \(String(format: "%.2f", commandBias))")
        }

        let preferredPathMatch: Double
        if let preferredPath = memoryInfluence.preferredFixPath,
           let contract = firstOperator.actionContract(
               for: plan.projectedState,
               goal: goal
           ),
           contract.workspaceRelativePath == preferredPath {
            preferredPathMatch = 0.08
            notes.append("preferred fix path match")
        } else {
            preferredPathMatch = 0
        }

        // ── Strategy-aware bias adjustments ──
        let strategyBoost = strategySpecificBias(
            strategy: selectedStrategy,
            plan: plan,
            memoryInfluence: memoryInfluence,
            notes: &notes
        )
        successBias += strategyBoost

        return MemoryDecisionBias(
            successPatternBias: successBias + preferredPathMatch,
            failurePatternPenalty: failurePenalty,
            projectSpecificBias: projectBias,
            recentTraceBias: commandBias,
            notes: notes
        )
    }

    /// Compute total bias score for a plan, optionally scoped by strategy.
    public func biasScore(
        plan: PlanCandidate,
        goal: Goal,
        worldState: WorldState,
        taskContext: TaskContext,
        selectedStrategy: SelectedStrategy
    ) -> Double {
        bias(
            plan: plan,
            goal: goal,
            worldState: worldState,
            taskContext: taskContext,
            selectedStrategy: selectedStrategy
        ).totalBias
    }

    // MARK: - Strategy-specific bias

    private func strategySpecificBias(
        strategy: SelectedStrategy,
        plan: PlanCandidate,
        memoryInfluence: MemoryInfluence,
        notes: inout [String]
    ) -> Double {
        var boost = 0.0

        switch strategy.kind {
        case .repoRepair:
            // Prefer dependency-update and patch-strategy success history.
            if memoryInfluence.preferredFixPath != nil {
                boost += 0.1
                notes.append("repoRepair: preferred fix path boost")
            }
            if plan.sourceType == .workflow {
                boost += 0.05
                notes.append("repoRepair: workflow-backed plan boost")
            }

        case .browserInteraction:
            // Penalize recently failed targets, prefer successful patterns.
            if memoryInfluence.riskPenalty > 0 {
                boost -= 0.08
                notes.append("browserInteraction: recent failure penalty")
            }
            if memoryInfluence.executionRankingBias > 0 {
                boost += 0.06
                notes.append("browserInteraction: successful target pattern boost")
            }

        case .workflowExecution:
            // Prefer high-confidence workflow matches.
            if plan.sourceType == .workflow {
                boost += 0.12
                notes.append("workflowExecution: workflow source boost")
            }

        case .recoveryMode:
            // Prefer recovery paths that resolved similar failures.
            if memoryInfluence.preferredRecoveryStrategy != nil {
                boost += 0.1
                notes.append("recoveryMode: preferred recovery strategy boost")
            }

        case .graphNavigation:
            // Prefer stable graph edges.
            if plan.sourceType == .stableGraph {
                boost += 0.08
                notes.append("graphNavigation: stable graph boost")
            }

        default:
            break
        }

        return boost
    }
}
