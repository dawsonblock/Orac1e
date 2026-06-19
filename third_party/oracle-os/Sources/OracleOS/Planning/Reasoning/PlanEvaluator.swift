import Foundation

public final class PlanEvaluator: @unchecked Sendable {
    private let workflowRetriever: WorkflowRetriever
    private let planSimulator: PlanSimulator

    public init(workflowRetriever: WorkflowRetriever) {
        self.workflowRetriever = workflowRetriever
        self.planSimulator = PlanSimulator(workflowRetriever: workflowRetriever)
    }

    public func evaluate(
        plans: [PlanCandidate],
        taskContext: TaskContext,
        goal: Goal,
        worldState: WorldState,
        graphStore: GraphStore,
        workflowIndex: WorkflowIndex,
memoryStore: UnifiedMemoryStore
    ) -> [PlanCandidate] {
        let memoryRouter = MemoryRouter(memoryStore: memoryStore)
        let memoryInfluence = memoryRouter.influence(
            for: MemoryQueryContext(
                taskContext: taskContext,
                worldState: worldState,
                errorSignature: goal.description
            )
        )
        let workflowMatch = workflowRetriever.retrieve(
            goal: goal,
            taskContext: taskContext,
            worldState: worldState,
            workflowIndex: workflowIndex,
            memoryStore: memoryStore,
            selectedStrategy: nil
        )

        return plans.compactMap { plan in
            guard let first = plan.operators.first,
                  let contract = first.actionContract(for: worldStateToReasoningState(taskContext: taskContext, worldState: worldState, memoryInfluence: memoryInfluence), goal: goal)
            else {
                return nil
            }

            var reasons: [String] = []
            var score = projectedGoalAlignment(plan.projectedState, goal: goal, taskContext: taskContext, reasons: &reasons)
            score += workflowSupport(
                contract: contract,
                workflowMatch: workflowMatch,
                reasons: &reasons
            )
            score += graphSupport(
                contract: contract,
                worldState: worldState,
                goal: goal,
                graphStore: graphStore,
                memoryStore: memoryStore,
                riskPenalty: plan.projectedState.riskPenalty,
                reasons: &reasons
            )
            score += memorySupport(
                contract: contract,
                state: plan.projectedState,
                goal: goal,
                memoryRouter: memoryRouter,
                reasons: &reasons
            )
            let simulatedOutcome = planSimulator.simulate(
                plan: plan,
                taskContext: taskContext,
                goal: goal,
                worldState: worldState,
                graphStore: graphStore,
                workflowIndex: workflowIndex,
                memoryStore: memoryStore
            )
            if let simulatedOutcome {
                score += simulatedOutcome.successProbability * 0.32
                score -= simulatedOutcome.riskScore * 0.16
                reasons.append("simulated success \(String(format: "%.2f", simulatedOutcome.successProbability))")
                if let likelyFailureMode = simulatedOutcome.likelyFailureMode {
                    reasons.append("simulated failure mode \(likelyFailureMode)")
                }
                reasons.append(contentsOf: simulatedOutcome.reasons)
            }
            score -= costPenalty(plan, reasons: &reasons)

            return PlanCandidate(
                operators: plan.operators,
                projectedState: plan.projectedState,
                score: score,
                reasons: reasons,
                simulatedOutcome: simulatedOutcome,
                sourceType: plan.sourceType
            )
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.operators.count < rhs.operators.count
            }
            return lhs.score > rhs.score
        }
    }

    public func chooseBestPlan(
        _ plans: [PlanCandidate],
        minimumScore: Double = 0.6
    ) -> PlanCandidate? {
        guard let best = plans.first, best.score >= minimumScore else {
            return nil
        }
        return best
    }

    private func graphSupport(
        contract: ActionContract,
        worldState: WorldState,
        goal: Goal,
        graphStore: GraphStore,
memoryStore: UnifiedMemoryStore,
        riskPenalty: Double,
        reasons: inout [String]
    ) -> Double {
        let scorer = PathScorer()
        let stable = graphStore.outgoingStableEdges(from: worldState.planningState.id)
            .compactMap { edge -> Double? in
                guard let edgeContract = graphStore.actionContract(for: edge.actionContractID),
                      contractsMatch(contract, edgeContract)
                else {
                    return nil
                }
                reasons.append("stable graph supports first step")
                return scorer.score(
                    edge: edge,
                    actionContract: edgeContract,
                    goal: goal,
                    memoryBias: 0,
                    riskPenalty: riskPenalty
                )
            }
            .max() ?? 0

        if stable > 0 {
            return 0.35 + (0.25 * stable)
        }

        let candidate = graphStore.outgoingCandidateEdges(from: worldState.planningState.id)
            .compactMap { edge -> Double? in
                guard let edgeContract = graphStore.actionContract(for: edge.actionContractID),
                      contractsMatch(contract, edgeContract)
                else {
                    return nil
                }
                reasons.append("candidate graph supports first step")
                return scorer.score(
                    edge: edge,
                    actionContract: edgeContract,
                    goal: goal,
                    memoryBias: 0,
                    riskPenalty: riskPenalty
                )
            }
            .max() ?? 0

        if candidate > 0 {
            return 0.2 + (0.15 * candidate)
        }

        return 0
    }

    private func workflowSupport(
        contract: ActionContract,
        workflowMatch: WorkflowMatch?,
        reasons: inout [String]
    ) -> Double {
        guard let workflowMatch,
              workflowMatch.stepIndex < workflowMatch.plan.steps.count
        else {
            return 0
        }

        let step = workflowMatch.plan.steps[workflowMatch.stepIndex]
        guard contractsMatch(contract, step.actionContract) else {
            return 0
        }

        reasons.append("workflow supports first step")
        return 0.25 + (0.15 * workflowMatch.score)
    }

    private func memorySupport(
        contract: ActionContract,
        state: ReasoningPlanningState,
        goal: Goal,
        memoryRouter: MemoryRouter,
        reasons: inout [String]
    ) -> Double {
        let bias = memoryRouter.workflowActionBias(
            contract: contract,
            app: state.activeApplication ?? state.targetApplication,
            goalDescription: goal.description,
            workspaceRoot: state.workspaceRoot
        )
        if bias > 0 {
            reasons.append("memory supports first step")
        }
        return bias
    }

    private func projectedGoalAlignment(
        _ state: ReasoningPlanningState,
        goal: Goal,
        taskContext: TaskContext,
        reasons: inout [String]
    ) -> Double {
        var score = 0.0

        if state.modalPresent == false {
            score += 0.15
            reasons.append("projected state clears modal blockers")
        }
        if let targetApp = goal.targetApp, state.activeApplication == targetApp {
            score += 0.2
            reasons.append("projected state matches target app")
        }
        if let targetDomain = goal.targetDomain, state.currentDomain == targetDomain {
            score += 0.2
            reasons.append("projected state matches target domain")
        }
        if taskContext.agentKind != .os && state.testsObserved {
            score += 0.15
            reasons.append("projected state observes test results")
        }
        if taskContext.agentKind != .os && state.patchApplied {
            score += 0.15
            reasons.append("projected state includes patch application")
        }
        return score
    }

    private func costPenalty(_ plan: PlanCandidate, reasons: inout [String]) -> Double {
        let totalCost = plan.operators.reduce(0.0) { partial, op in
            partial + op.baseCost + op.risk
        }
        let penalty = min(totalCost * 0.08, 0.45)
        reasons.append("plan cost penalty \(String(format: "%.2f", penalty))")
        return penalty
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

    private func worldStateToReasoningState(
        taskContext: TaskContext,
        worldState: WorldState,
        memoryInfluence: MemoryInfluence
    ) -> ReasoningPlanningState {
        ReasoningPlanningState(
            taskContext: taskContext,
            worldState: worldState,
            memoryInfluence: memoryInfluence
        )
    }
}
