import Foundation

public struct PromptContext: Sendable, Equatable {
    public let templateKind: PromptTemplateKind
    public let goal: String
    public let context: [String]
    public let state: [String]
    public let constraints: [String]
    public let availableActions: [String]
    public let relevantKnowledge: [String]
    public let expectedOutput: [String]
    public let evaluationCriteria: [String]

    public init(
        templateKind: PromptTemplateKind,
        goal: String,
        context: [String],
        state: [String],
        constraints: [String],
        availableActions: [String],
        relevantKnowledge: [String],
        expectedOutput: [String],
        evaluationCriteria: [String]
    ) {
        self.templateKind = templateKind
        self.goal = goal
        self.context = context
        self.state = state
        self.constraints = constraints
        self.availableActions = availableActions
        self.relevantKnowledge = relevantKnowledge
        self.expectedOutput = expectedOutput
        self.evaluationCriteria = evaluationCriteria
    }
}

public struct ContextAssembler {
    public init() {}

    public func planning(
        goal: Goal,
        taskContext: TaskContext,
        worldState: WorldState,
        selectedOperators: [String],
        candidatePlans: [ScoredPlanSummary],
        fallbackReason: String?,
        projectMemoryRefs: [ProjectMemoryRef],
        notes: [String],
        template: PromptTemplate
    ) -> PromptContext {
        let context = baseContext(taskContext: taskContext, worldState: worldState)
            + [
                "Planner family: \(taskContext.agentKind.rawValue)",
                "Selected operators: \(selectedOperators.joined(separator: " -> "))",
            ]
            + candidatePlanContext(candidatePlans)

        let state = currentState(worldState: worldState)
            + [
                "Fallback reason: \(fallbackReason ?? "none")",
            ]

        let knowledge = repositoryKnowledge(snapshot: worldState.repositorySnapshot)
            + memoryKnowledge(projectMemoryRefs: projectMemoryRefs)
            + notes.map { "Note: \($0)" }

        return PromptContext(
            templateKind: .planning,
            goal: goal.description,
            context: context,
            state: state,
            constraints: [],
            availableActions: template.defaultActions,
            relevantKnowledge: knowledge,
            expectedOutput: template.expectedOutput,
            evaluationCriteria: template.evaluationCriteria
        )
    }

    public func workflowSelection(
        goal: Goal,
        taskContext: TaskContext,
        worldState: WorldState,
        match: WorkflowMatch,
        template: PromptTemplate
    ) -> PromptContext {
        let context = baseContext(taskContext: taskContext, worldState: worldState) + [
            "Workflow ID: \(match.plan.id)",
            "Workflow score: \(String(format: "%.2f", match.score))",
            "Workflow step index: \(match.stepIndex)",
        ]
        let state = currentState(worldState: worldState)
        let knowledge = workflowKnowledge(plan: match.plan) + memoryKnowledge(projectMemoryRefs: match.projectMemoryRefs)
        return PromptContext(
            templateKind: .workflowSelection,
            goal: goal.description,
            context: context,
            state: state,
            constraints: [],
            availableActions: template.defaultActions,
            relevantKnowledge: knowledge,
            expectedOutput: template.expectedOutput,
            evaluationCriteria: template.evaluationCriteria
        )
    }

    public func codeRepair(
        taskContext: TaskContext,
        worldState: WorldState,
        snapshot: RepositorySnapshot,
        candidatePaths: [String],
        projectMemoryRefs: [ProjectMemoryRef],
        architectureFindings: [ArchitectureFinding],
        notes: [String],
        executionMode: PlannerExecutionMode,
        template: PromptTemplate
    ) -> PromptContext {
        let context = baseContext(taskContext: taskContext, worldState: worldState) + [
            "Execution mode: \(executionMode.rawValue)",
            "Repository root: \(snapshot.workspaceRoot)",
            "Build system: \(snapshot.buildTool.rawValue)",
            "Active branch: \(snapshot.activeBranch ?? "detached")",
            "Workspace state: \(snapshot.isGitDirty ? "dirty" : "clean")",
        ]

        let state = currentState(worldState: worldState) + [
            "Candidate paths: \(candidatePaths.isEmpty ? "none" : candidatePaths.joined(separator: ", "))",
        ]

        let knowledge = repositoryKnowledge(snapshot: snapshot, preferredPaths: candidatePaths)
            + memoryKnowledge(projectMemoryRefs: projectMemoryRefs)
            + architectureKnowledge(findings: architectureFindings)
            + notes.map { "Note: \($0)" }

        return PromptContext(
            templateKind: .codeRepair,
            goal: taskContext.goal.description,
            context: context,
            state: state,
            constraints: [],
            availableActions: template.defaultActions,
            relevantKnowledge: knowledge,
            expectedOutput: template.expectedOutput,
            evaluationCriteria: template.evaluationCriteria
        )
    }

    public func osAction(
        goal: Goal,
        worldState: WorldState,
        actionContract: ActionContract,
        semanticQuery: ElementQuery?,
        source: PlannerSource,
        fallbackReason: String?,
        notes: [String],
        template: PromptTemplate
    ) -> PromptContext {
        let context = [
            "Planner source: \(source.rawValue)",
            "Active app: \(worldState.observation.app ?? "unknown")",
            "Window title: \(worldState.observation.windowTitle ?? "unknown")",
            "Action contract: \(actionContract.skillName)",
        ]

        let targetState: [String]
        if let semanticQuery {
            targetState = [
                "Target query text: \(semanticQuery.text ?? "none")",
                "Target query role: \(semanticQuery.role ?? "none")",
                "Target query app: \(semanticQuery.app ?? worldState.observation.app ?? "unknown")",
            ]
        } else {
            targetState = [
                "Target label: \(actionContract.targetLabel ?? "none")",
                "Target role: \(actionContract.targetRole ?? "none")",
            ]
        }

        let state = currentState(worldState: worldState)
            + targetState
            + ["Fallback reason: \(fallbackReason ?? "none")"]

        let knowledge = notes.map { "Note: \($0)" }

        return PromptContext(
            templateKind: .osAction,
            goal: goal.description,
            context: context,
            state: state,
            constraints: [],
            availableActions: template.defaultActions,
            relevantKnowledge: knowledge,
            expectedOutput: template.expectedOutput,
            evaluationCriteria: template.evaluationCriteria
        )
    }

    public func experimentGeneration(
        spec: ExperimentSpec,
        snapshot: RepositorySnapshot?,
        template: PromptTemplate
    ) -> PromptContext {
        let context = [
            "Workspace root: \(spec.workspaceRoot)",
            "Candidate count: \(spec.candidates.count)",
            "Build command: \(spec.buildCommand?.summary ?? "auto-detect")",
            "Test command: \(spec.testCommand?.summary ?? "auto-detect")",
        ]

        let state = [
            "Build system: \(snapshot?.buildTool.rawValue ?? "unknown")",
            "Active branch: \(snapshot?.activeBranch ?? "detached")",
            "Workspace state: \((snapshot?.isGitDirty ?? false) ? "dirty" : "clean")",
        ]

        let knowledge = repositoryKnowledge(snapshot: snapshot, preferredPaths: spec.candidates.map(\.workspaceRelativePath))
            + spec.candidates.map {
                "Candidate \($0.id): \($0.workspaceRelativePath) -> \($0.summary)"
            }

        return PromptContext(
            templateKind: .experimentGeneration,
            goal: spec.goalDescription,
            context: context,
            state: state,
            constraints: [],
            availableActions: template.defaultActions,
            relevantKnowledge: knowledge,
            expectedOutput: template.expectedOutput,
            evaluationCriteria: template.evaluationCriteria
        )
    }

    public func recoverySelection(
        failure: FailureClass,
        state: WorldState,
        orderedStrategies: [String],
        preferredStrategy: String?,
        template: PromptTemplate
    ) -> PromptContext {
        let context = [
            "Failure class: \(failure.rawValue)",
            "Active app: \(state.observation.app ?? "unknown")",
            "Visible element count: \(state.observation.elements.count)",
        ]

        let current = currentState(worldState: state) + [
            "Preferred remembered strategy: \(preferredStrategy ?? "none")",
            "Candidate recovery strategies: \(orderedStrategies.joined(separator: ", "))",
        ]

        return PromptContext(
            templateKind: .recoverySelection,
            goal: "Recover from \(failure.rawValue)",
            context: context,
            state: current,
            constraints: [],
            availableActions: template.defaultActions,
            relevantKnowledge: orderedStrategies.map { "Strategy candidate: \($0)" },
            expectedOutput: template.expectedOutput,
            evaluationCriteria: template.evaluationCriteria
        )
    }

    private func baseContext(taskContext: TaskContext, worldState: WorldState) -> [String] {
        var context = [
            "Task family: \(taskContext.agentKind.rawValue)",
            "Planning state: \(worldState.planningState.id.rawValue)",
            "Current app: \(worldState.observation.app ?? "unknown")",
            "Task phases: \(taskContext.phases.map(\.rawValue).joined(separator: ", "))",
        ]
        if let windowTitle = worldState.observation.windowTitle {
            context.append("Window title: \(windowTitle)")
        }
        if let url = worldState.observation.url {
            context.append("Current URL: \(url)")
            if let domain = URL(string: url)?.host {
                context.append("Current domain: \(domain)")
            }
        }
        return context
    }

    private func currentState(worldState: WorldState) -> [String] {
        var state = [
            "Observation hash: \(worldState.observationHash)",
            "Planning state cluster: \(worldState.planningState.clusterKey.rawValue)",
            "Task phase: \(worldState.planningState.taskPhase ?? "unknown")",
            "Modal class: \(worldState.planningState.modalClass ?? "none")",
            "Last action: \(worldState.lastAction?.action ?? "none")",
        ]
        if let focusedElementID = worldState.observation.focusedElementID {
            state.append("Focused element: \(focusedElementID)")
        }
        state.append("Visible elements: \(worldState.observation.elements.count)")
        return state
    }

    private func repositoryKnowledge(
        snapshot: RepositorySnapshot?,
        preferredPaths: [String] = []
    ) -> [String] {
        guard let snapshot else { return [] }

        var lines = [
            "Indexed files: \(snapshot.files.filter { !$0.isDirectory }.count)",
            "Symbols: \(snapshot.symbolGraph.nodes.count)",
            "Dependencies: \(snapshot.dependencyGraph.edges.count)",
            "Calls: \(snapshot.callGraph.edges.count)",
            "Tests mapped: \(snapshot.testGraph.edges.count)",
        ]
        if !preferredPaths.isEmpty {
            lines.append("Preferred relevant files: \(preferredPaths.prefix(5).joined(separator: ", "))")
        }
        return lines
    }

    private func memoryKnowledge(projectMemoryRefs: [ProjectMemoryRef]) -> [String] {
        projectMemoryRefs.prefix(6).map { ref in
            "Project memory: [\(ref.kind.rawValue)] \(ref.title)"
        }
    }

    private func workflowKnowledge(plan: WorkflowPlan) -> [String] {
        [
            "Workflow goal pattern: \(plan.goalPattern)",
            "Workflow success rate: \(String(format: "%.2f", plan.successRate))",
            "Workflow replay validation: \(String(format: "%.2f", plan.replayValidationSuccess))",
            "Workflow repeated trace segments: \(plan.repeatedTraceSegmentCount)",
        ] + plan.parameterSlots.prefix(4).map { "Workflow parameter slot: \($0)" }
    }

    private func architectureKnowledge(findings: [ArchitectureFinding]) -> [String] {
        findings.prefix(4).map { finding in
            "Architecture finding: \(finding.title) (\(finding.severity.rawValue))"
        }
    }

    private func candidatePlanContext(_ candidatePlans: [ScoredPlanSummary]) -> [String] {
        candidatePlans.prefix(3).map { summary in
            "Candidate plan [score \(String(format: "%.2f", summary.score))]: \(summary.operatorNames.joined(separator: " -> "))"
        }
    }
}
