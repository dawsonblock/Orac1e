import Foundation

public struct WorkflowMatch: Sendable {
    public let plan: WorkflowPlan
    public let stepIndex: Int
    public let score: Double
    public let projectMemoryRefs: [ProjectMemoryRef]

    public init(
        plan: WorkflowPlan,
        stepIndex: Int,
        score: Double,
        projectMemoryRefs: [ProjectMemoryRef] = []
    ) {
        self.plan = plan
        self.stepIndex = stepIndex
        self.score = score
        self.projectMemoryRefs = projectMemoryRefs
    }
}

public struct WorkflowRetriever: Sendable {
    public init() {}

    /// Retrieve the best matching workflow, optionally scoped by strategy.
    public func retrieve(
        goal: Goal,
        taskContext: TaskContext,
        worldState: WorldState,
        workflowIndex: WorkflowIndex,
        memoryStore: UnifiedMemoryStore? = nil,
        selectedStrategy: SelectedStrategy? = nil
    ) -> WorkflowMatch? {
        let memoryRouter = MemoryRouter(memoryStore: memoryStore)
        let memoryInfluence = memoryRouter.influence(
            for: MemoryQueryContext(
                taskContext: taskContext,
                worldState: worldState
            )
        )
        let projectMemorySignals = memoryInfluence.projectMemorySignals
        return workflowIndex.promotedPlans(for: taskContext.agentKind)
            .compactMap { plan -> WorkflowMatch? in
                // ── Strategy filter: skip workflows outside strategy scope ──
                if let selectedStrategy {
                    let workflowKind = inferStrategyKind(for: plan)
                    let allowsAllFamilies = Set(selectedStrategy.allowedOperatorFamilies) == Set(OperatorFamily.allCases)
                    if !allowsAllFamilies,
                       workflowKind != selectedStrategy.kind,
                       workflowKind != .graphNavigation {
                        return nil
                    }
                }

                guard let stepIndex = matchingStepIndex(plan: plan, planningStateID: worldState.planningState.id.rawValue) else {
                    return nil
                }
                let score = planScore(
                    plan: plan,
                    goal: goal,
                    stepIndex: stepIndex,
                    taskContext: taskContext,
                    worldState: worldState,
                    projectMemorySignals: projectMemorySignals,
                    memoryInfluence: memoryInfluence,
                    memoryRouter: memoryRouter
                )
                guard score > 0 else {
                    return nil
                }
                return WorkflowMatch(
                    plan: plan,
                    stepIndex: stepIndex,
                    score: score,
                    projectMemoryRefs: memoryInfluence.projectMemoryRefs
                )
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.plan.successRate > rhs.plan.successRate
                }
                return lhs.score > rhs.score
            }
            .first
    }

    private func matchingStepIndex(plan: WorkflowPlan, planningStateID: String) -> Int? {
        if let index = plan.steps.firstIndex(where: { $0.fromPlanningStateID == planningStateID }) {
            return index
        }
        if let firstIndex = plan.steps.firstIndex(where: { $0.fromPlanningStateID == nil }) {
            return firstIndex
        }
        return nil
    }

    private func planScore(
        plan: WorkflowPlan,
        goal: Goal,
        stepIndex: Int,
        taskContext: TaskContext,
        worldState: WorldState,
        projectMemorySignals: ProjectMemoryPlanningSignals,
        memoryInfluence: MemoryInfluence,
        memoryRouter: MemoryRouter
    ) -> Double {
        let normalizedGoal = goal.description.lowercased()
        let normalizedPattern = plan.goalPattern.lowercased()
        let tokens = Set(normalizedPattern.split(separator: " ").map(String.init))
        let overlap = tokens.isEmpty ? 0 : tokens.filter { normalizedGoal.contains($0) }.count
        let matchRatio = tokens.isEmpty ? 0 : Double(overlap) / Double(tokens.count)
        let stepPenalty = Double(stepIndex) * 0.05
        let memoryBias = workflowMemoryBias(
            plan: plan,
            stepIndex: stepIndex,
            taskContext: taskContext,
            worldState: worldState,
            projectMemorySignals: projectMemorySignals,
            memoryInfluence: memoryInfluence,
            memoryRouter: memoryRouter
        )
        return max(0, (0.5 * matchRatio) + (0.35 * plan.successRate) + memoryBias - stepPenalty)
    }

    private func workflowMemoryBias(
        plan: WorkflowPlan,
        stepIndex: Int,
        taskContext: TaskContext,
        worldState: WorldState,
        projectMemorySignals: ProjectMemoryPlanningSignals,
        memoryInfluence: MemoryInfluence,
        memoryRouter: MemoryRouter
    ) -> Double {
        let currentStep = plan.steps[stepIndex]
        guard let snapshot = worldState.repositorySnapshot else {
            return memoryRouter.workflowActionBias(
                contract: currentStep.actionContract,
                app: worldState.observation.app,
                goalDescription: taskContext.goal.description,
                workspaceRoot: taskContext.workspaceRoot
            )
        }

        let workflowPaths = Set(plan.steps.compactMap { $0.actionContract.workspaceRelativePath })
        let preferredPaths = Set(projectMemorySignals.preferredPaths(in: snapshot))
        let avoidedPaths = Set(projectMemorySignals.avoidedPaths(in: snapshot))

        var bias = 0.0
        if workflowPaths.isEmpty == false && workflowPaths.isSubset(of: preferredPaths) {
            bias += 0.2
        }
        if workflowPaths.contains(where: avoidedPaths.contains) {
            bias -= 0.25
        }
        if let preferredFixPath = memoryInfluence.preferredFixPath,
           workflowPaths.contains(preferredFixPath) {
            bias += 0.15
        }
        if projectMemorySignals.hasKnownGoodPatterns {
            bias += 0.05
        }
        if projectMemorySignals.hasArchitectureDecisions {
            bias += 0.05
        }
        if projectMemorySignals.hasRejectedApproaches {
            bias -= 0.1
        }
        if projectMemorySignals.hasOpenProblems {
            bias -= 0.1
        }
        bias += memoryRouter.workflowActionBias(
            contract: currentStep.actionContract,
            app: worldState.observation.app,
            goalDescription: taskContext.goal.description,
            workspaceRoot: taskContext.workspaceRoot
        )
        return bias
    }

    /// Infer the strategy kind for a workflow based on its steps.
    private func inferStrategyKind(for plan: WorkflowPlan) -> StrategyKind {
        let skills = plan.steps.map { $0.actionContract.skillName.lowercased() }
        return StrategyKind.infer(fromSkills: skills)
    }

}
