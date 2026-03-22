import Foundation

public enum PlannerSource: String, Codable, Sendable {
    case workflow
    case stableGraph = "stable_graph"
    case candidateGraph = "candidate_graph"
    case exploration
    case reasoning
    case llm
    case recovery
    case strategy
}

public enum PlannerExecutionMode: String, Codable, Sendable {
    case direct
    case experiment
}

public struct PlannerDecision: Sendable {
    public let agentKind: AgentKind
    public let skillName: String
    public let plannerFamily: PlannerFamily
    public let stepPhase: TaskStepPhase
    public let executionMode: PlannerExecutionMode
    public let actionContract: ActionContract
    public let source: PlannerSource
    public let workflowID: String?
    public let workflowStepID: String?
    public let pathEdgeIDs: [String]
    public let currentEdgeID: String?
    public let fallbackReason: String?
    public let graphSearchDiagnostics: GraphSearchDiagnostics?
    public let semanticQuery: ElementQuery?
    public let projectMemoryRefs: [ProjectMemoryRef]
    public let architectureFindings: [ArchitectureFinding]
    public let refactorProposalID: String?
    public let experimentSpec: ExperimentSpec?
    public let experimentDecision: ExperimentDecision?
    public let experimentCandidateID: String?
    public let experimentSandboxPath: String?
    public let selectedExperimentCandidate: Bool?
    public let experimentOutcome: String?
    public let knowledgeTier: KnowledgeTier
    public let notes: [String]
    public let planDiagnostics: PlanDiagnostics?
    public let promptDiagnostics: PromptDiagnostics?
    public let recoveryTagged: Bool
    public let recoveryStrategy: String?
    public let recoverySource: String?

    public init(
        agentKind: AgentKind = .os,
        skillName: String? = nil,
        plannerFamily: PlannerFamily = .os,
        stepPhase: TaskStepPhase = .operatingSystem,
        executionMode: PlannerExecutionMode = .direct,
        actionContract: ActionContract,
        source: PlannerSource,
        workflowID: String? = nil,
        workflowStepID: String? = nil,
        pathEdgeIDs: [String] = [],
        currentEdgeID: String? = nil,
        fallbackReason: String? = nil,
        graphSearchDiagnostics: GraphSearchDiagnostics? = nil,
        semanticQuery: ElementQuery? = nil,
        projectMemoryRefs: [ProjectMemoryRef] = [],
        architectureFindings: [ArchitectureFinding] = [],
        refactorProposalID: String? = nil,
        experimentSpec: ExperimentSpec? = nil,
        experimentDecision: ExperimentDecision? = nil,
        experimentCandidateID: String? = nil,
        experimentSandboxPath: String? = nil,
        selectedExperimentCandidate: Bool? = nil,
        experimentOutcome: String? = nil,
        knowledgeTier: KnowledgeTier? = nil,
        notes: [String] = [],
        planDiagnostics: PlanDiagnostics? = nil,
        promptDiagnostics: PromptDiagnostics? = nil,
        recoveryTagged: Bool = false,
        recoveryStrategy: String? = nil,
        recoverySource: String? = nil
    ) {
        self.agentKind = agentKind
        self.skillName = skillName ?? actionContract.skillName
        self.plannerFamily = plannerFamily
        self.stepPhase = stepPhase
        self.executionMode = executionMode
        self.actionContract = actionContract
        self.source = source
        self.workflowID = workflowID
        self.workflowStepID = workflowStepID
        self.pathEdgeIDs = pathEdgeIDs
        self.currentEdgeID = currentEdgeID
        self.fallbackReason = fallbackReason
        self.graphSearchDiagnostics = graphSearchDiagnostics
        self.semanticQuery = semanticQuery
        self.projectMemoryRefs = projectMemoryRefs
        self.architectureFindings = architectureFindings
        self.refactorProposalID = refactorProposalID
        self.experimentSpec = experimentSpec
        self.experimentDecision = experimentDecision
        self.experimentCandidateID = experimentCandidateID
        self.experimentSandboxPath = experimentSandboxPath
        self.selectedExperimentCandidate = selectedExperimentCandidate
        self.experimentOutcome = experimentOutcome
        self.knowledgeTier = knowledgeTier ?? (recoveryTagged ? .recovery : (source == .exploration ? .exploration : .candidate))
        self.notes = notes
        self.planDiagnostics = planDiagnostics
        self.promptDiagnostics = promptDiagnostics
        self.recoveryTagged = recoveryTagged
        self.recoveryStrategy = recoveryStrategy
        self.recoverySource = recoverySource
    }

    public func with(promptDiagnostics: PromptDiagnostics?) -> PlannerDecision {
        PlannerDecision(
            agentKind: agentKind,
            skillName: skillName,
            plannerFamily: plannerFamily,
            stepPhase: stepPhase,
            executionMode: executionMode,
            actionContract: actionContract,
            source: source,
            workflowID: workflowID,
            workflowStepID: workflowStepID,
            pathEdgeIDs: pathEdgeIDs,
            currentEdgeID: currentEdgeID,
            fallbackReason: fallbackReason,
            graphSearchDiagnostics: graphSearchDiagnostics,
            semanticQuery: semanticQuery,
            projectMemoryRefs: projectMemoryRefs,
            architectureFindings: architectureFindings,
            refactorProposalID: refactorProposalID,
            experimentSpec: experimentSpec,
            experimentDecision: experimentDecision,
            experimentCandidateID: experimentCandidateID,
            experimentSandboxPath: experimentSandboxPath,
            selectedExperimentCandidate: selectedExperimentCandidate,
            experimentOutcome: experimentOutcome,
            knowledgeTier: knowledgeTier,
            notes: notes,
            planDiagnostics: planDiagnostics,
            promptDiagnostics: promptDiagnostics,
            recoveryTagged: recoveryTagged,
            recoveryStrategy: recoveryStrategy,
            recoverySource: recoverySource
        )
    }

    public func normalized(
        fallbackReason: String? = nil,
        notes: [String]? = nil
    ) -> PlannerDecision {
        PlannerDecision(
            agentKind: agentKind,
            skillName: skillName,
            plannerFamily: plannerFamily,
            stepPhase: stepPhase,
            executionMode: executionMode,
            actionContract: actionContract,
            source: source,
            workflowID: workflowID,
            workflowStepID: workflowStepID,
            pathEdgeIDs: pathEdgeIDs,
            currentEdgeID: currentEdgeID,
            fallbackReason: fallbackReason ?? self.fallbackReason,
            graphSearchDiagnostics: graphSearchDiagnostics,
            semanticQuery: semanticQuery,
            projectMemoryRefs: projectMemoryRefs,
            architectureFindings: architectureFindings,
            refactorProposalID: refactorProposalID,
            experimentSpec: experimentSpec,
            experimentDecision: experimentDecision,
            experimentCandidateID: experimentCandidateID,
            experimentSandboxPath: experimentSandboxPath,
            selectedExperimentCandidate: selectedExperimentCandidate,
            experimentOutcome: experimentOutcome,
            knowledgeTier: knowledgeTier,
            notes: notes ?? self.notes,
            planDiagnostics: planDiagnostics,
            promptDiagnostics: promptDiagnostics,
            recoveryTagged: recoveryTagged,
            recoveryStrategy: recoveryStrategy,
            recoverySource: recoverySource
        )
    }
}
