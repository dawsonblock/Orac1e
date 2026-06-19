import Foundation

public struct SimulatedOutcome: Sendable, Equatable {
    public let successProbability: Double
    public let estimatedSteps: Int
    public let riskScore: Double
    public let likelyFailureMode: String?
    public let reasons: [String]

    public init(
        successProbability: Double,
        estimatedSteps: Int,
        riskScore: Double,
        likelyFailureMode: String? = nil,
        reasons: [String] = []
    ) {
        self.successProbability = successProbability
        self.estimatedSteps = estimatedSteps
        self.riskScore = riskScore
        self.likelyFailureMode = likelyFailureMode
        self.reasons = reasons
    }
}

public final class PlanSimulator: @unchecked Sendable {
    private let workflowRetriever: WorkflowRetriever

    public init(workflowRetriever: WorkflowRetriever) {
        self.workflowRetriever = workflowRetriever
    }

    public func simulate(
        plan: PlanCandidate,
        taskContext: TaskContext,
        goal: Goal,
        worldState: WorldState,
        graphStore: GraphStore,
        workflowIndex: WorkflowIndex,
memoryStore: UnifiedMemoryStore
    ) -> SimulatedOutcome? {
        guard let first = plan.operators.first else {
            return nil
        }

        let memoryRouter = MemoryRouter(memoryStore: memoryStore)
        let memoryInfluence = memoryRouter.influence(
            for: MemoryQueryContext(
                taskContext: taskContext,
                worldState: worldState,
                errorSignature: goal.description
            )
        )
        let reasoningState = ReasoningPlanningState(
            taskContext: taskContext,
            worldState: worldState,
            memoryInfluence: memoryInfluence
        )
        guard let contract = first.actionContract(for: reasoningState, goal: goal) else {
            return nil
        }

        var probability = 0.4
        var reasons: [String] = []
        var failureMode: String?

        if plan.projectedState.modalPresent == false, reasoningState.modalPresent {
            probability += 0.18
            reasons.append("projected state clears modal blocker")
        }
        if let targetApp = goal.targetApp, plan.projectedState.activeApplication == targetApp {
            probability += 0.14
            reasons.append("projected state reaches target application")
        }
        if let targetDomain = goal.targetDomain, plan.projectedState.currentDomain == targetDomain {
            probability += 0.12
            reasons.append("projected state reaches target domain")
        }
        if taskContext.agentKind != .os, plan.projectedState.testsObserved {
            probability += 0.08
            reasons.append("projected state observes test results")
        }
        if taskContext.agentKind != .os, plan.projectedState.patchApplied {
            probability += 0.08
            reasons.append("projected state includes candidate patch application")
        }

        switch first.kind {
        case .dismissModal:
            probability += reasoningState.modalPresent ? 0.25 : -0.1
            if reasoningState.modalPresent == false {
                failureMode = "no-modal-present"
            }
        case .openApplication:
            probability += reasoningState.targetApplication == nil ? -0.1 : 0.18
            if reasoningState.targetApplication == nil {
                failureMode = "missing-target-application"
            }
        case .navigateBrowser:
            probability += reasoningState.targetDomain == nil ? -0.1 : 0.16
            if reasoningState.targetDomain == nil {
                failureMode = "missing-target-domain"
            }
        case .clickTarget:
            probability += reasoningState.visibleTargets.isEmpty ? -0.18 : 0.12
            if reasoningState.visibleTargets.isEmpty {
                failureMode = "no-visible-targets"
            }
        case .applyPatch:
            if reasoningState.candidateWorkspacePaths.isEmpty {
                probability -= 0.22
                failureMode = "no-candidate-paths"
            } else {
                probability += 0.14
                reasons.append("candidate workspace paths exist")
            }
            if reasoningState.preferredWorkspacePath != nil {
                probability += 0.1
                reasons.append("memory prefers a specific patch path")
            } else if reasoningState.candidateWorkspacePaths.count > 1 {
                probability -= 0.08
                failureMode = failureMode ?? "ambiguous-edit-target"
            }
        case .runTests, .rerunTests:
            probability += reasoningState.repoOpen ? 0.16 : -0.12
            if reasoningState.repoOpen == false {
                failureMode = "repository-not-open"
            }
        case .buildProject:
            probability += reasoningState.repoOpen ? 0.14 : -0.12
            if reasoningState.repoOpen == false {
                failureMode = "repository-not-open"
            }
        case .revertPatch:
            probability += reasoningState.patchApplied ? 0.12 : -0.08
            if reasoningState.patchApplied == false {
                failureMode = "no-patch-to-revert"
            }
        case .retryWithAlternateTarget:
            probability += reasoningState.visibleTargets.count > 1 ? 0.12 : -0.08
            if reasoningState.visibleTargets.isEmpty {
                failureMode = "no-visible-targets"
            }
        case .focusWindow:
            probability += reasoningState.targetApplication != nil ? 0.18 : -0.1
            if reasoningState.targetApplication == nil {
                failureMode = "missing-target-application"
            }
        case .restartApplication:
            probability += reasoningState.targetApplication != nil ? 0.1 : -0.15
            if reasoningState.targetApplication == nil {
                failureMode = "missing-target-application"
            }
        case .rollbackPatch:
            probability += reasoningState.patchApplied ? 0.14 : -0.08
            if reasoningState.patchApplied == false {
                failureMode = "no-patch-to-rollback"
            }
        }

        let workflowMatch = workflowRetriever.retrieve(
            goal: goal,
            taskContext: taskContext,
            worldState: worldState,
            workflowIndex: workflowIndex,
            memoryStore: memoryStore,
            selectedStrategy: nil
        )
        if let workflowMatch,
           workflowMatch.stepIndex < workflowMatch.plan.steps.count,
           contractsMatch(contract, workflowMatch.plan.steps[workflowMatch.stepIndex].actionContract)
        {
            let workflowBonus = 0.08 + (workflowMatch.score * 0.08)
            probability += workflowBonus
            reasons.append("workflow replay history supports this first step")
        }

        if stableGraphSupports(contract: contract, worldState: worldState, graphStore: graphStore) {
            probability += 0.14
            reasons.append("stable graph supports this first step")
        } else if candidateGraphSupports(contract: contract, worldState: worldState, graphStore: graphStore) {
            probability += 0.07
            reasons.append("candidate graph supports this first step")
        }

        let memoryBias = memoryRouter.workflowActionBias(
            contract: contract,
            app: reasoningState.activeApplication ?? reasoningState.targetApplication,
            goalDescription: goal.description,
            workspaceRoot: reasoningState.workspaceRoot
        )
        if memoryBias > 0 {
            probability += min(memoryBias, 0.12)
            reasons.append("execution or pattern memory supports this first step")
        }

        if reasoningState.modalPresent && first.kind != .dismissModal && taskContext.agentKind != .code {
            probability -= 0.1
            failureMode = failureMode ?? "modal-blocked"
        }

        let averageOperatorRisk = plan.operators.map(\.risk).reduce(0, +) / Double(max(plan.operators.count, 1))
        let riskScore = min(
            1,
            plan.projectedState.riskPenalty
                + averageOperatorRisk * 0.9
                + Double(max(plan.operators.count - 1, 0)) * 0.05
        )
        probability -= riskScore * 0.18
        reasons.append("simulated risk \(String(format: "%.2f", riskScore))")

        return SimulatedOutcome(
            successProbability: min(max(probability, 0.05), 0.98),
            estimatedSteps: plan.operators.count,
            riskScore: riskScore,
            likelyFailureMode: failureMode,
            reasons: reasons
        )
    }

    private func stableGraphSupports(
        contract: ActionContract,
        worldState: WorldState,
        graphStore: GraphStore
    ) -> Bool {
        graphStore.outgoingStableEdges(from: worldState.planningState.id).contains { edge in
            guard let edgeContract = graphStore.actionContract(for: edge.actionContractID) else {
                return false
            }
            return contractsMatch(contract, edgeContract)
        }
    }

    private func candidateGraphSupports(
        contract: ActionContract,
        worldState: WorldState,
        graphStore: GraphStore
    ) -> Bool {
        graphStore.outgoingCandidateEdges(from: worldState.planningState.id).contains { edge in
            guard let edgeContract = graphStore.actionContract(for: edge.actionContractID) else {
                return false
            }
            return contractsMatch(contract, edgeContract)
        }
    }

    private func contractsMatch(_ lhs: ActionContract, _ rhs: ActionContract) -> Bool {
        guard lhs.skillName == rhs.skillName else {
            return false
        }
        if let lhsPath = lhs.workspaceRelativePath, let rhsPath = rhs.workspaceRelativePath, lhsPath == rhsPath {
            return true
        }
        let lhsLabel = lhs.targetLabel?.lowercased()
        let rhsLabel = rhs.targetLabel?.lowercased()
        if lhsLabel == nil && rhsLabel == nil {
            return true
        }
        if lhsLabel == rhsLabel {
            return true
        }
        if let lhsLabel, let rhsLabel {
            return lhsLabel.contains(rhsLabel) || rhsLabel.contains(lhsLabel)
        }
        return false
    }
}
