import Foundation

public final class MixedTaskPlanner: @unchecked Sendable {
    private let osPlanner: OSPlanner
    private let codePlanner: CodePlanner

    public init(
        osPlanner: OSPlanner = OSPlanner(),
        codePlanner: CodePlanner = CodePlanner()
    ) {
        self.osPlanner = osPlanner
        self.codePlanner = codePlanner
    }

    public func nextStep(
        taskContext: TaskContext,
        worldState: WorldState,
        graphStore: GraphStore,
        memoryStore: UnifiedMemoryStore,
        selectedStrategy: SelectedStrategy
    ) -> PlannerDecision? {
        let description = taskContext.goal.description.lowercased()
        let needsFinder = description.contains("finder") || description.contains("open repo")

        if needsFinder, (worldState.observation.app ?? "").localizedCaseInsensitiveContains("finder") == false {
            let handoffContext = TaskContext(
                goal: Goal(
                    description: taskContext.goal.description,
                    targetApp: "Finder",
                    targetDomain: nil,
                    targetTaskPhase: taskContext.goal.targetTaskPhase,
                    workspaceRoot: taskContext.workspaceRoot,
                    preferredAgentKind: .os
                ),
                agentKind: .os,
                workspaceRoot: taskContext.workspaceRoot,
                phases: taskContext.phases,
                projectMemoryRoot: taskContext.projectMemoryRoot,
                experimentsRoot: taskContext.experimentsRoot,
                maxExperimentCandidates: taskContext.maxExperimentCandidates,
                experimentCandidates: taskContext.experimentCandidates
            )
            guard let step = osPlanner.nextStep(
                taskContext: handoffContext,
                worldState: worldState,
                graphStore: graphStore,
                memoryStore: memoryStore,
                selectedStrategy: selectedStrategy
            ) else {
                return nil
            }
            return PlannerDecision(
                agentKind: .os,
                skillName: step.skillName,
                plannerFamily: .mixed,
                stepPhase: .handoff,
                executionMode: step.executionMode,
                actionContract: step.actionContract,
                source: step.source,
                workflowID: step.workflowID,
                workflowStepID: step.workflowStepID,
                pathEdgeIDs: step.pathEdgeIDs,
                currentEdgeID: step.currentEdgeID,
                fallbackReason: step.fallbackReason,
                graphSearchDiagnostics: step.graphSearchDiagnostics,
                semanticQuery: step.semanticQuery,
                projectMemoryRefs: step.projectMemoryRefs,
                architectureFindings: step.architectureFindings,
                refactorProposalID: step.refactorProposalID,
                experimentSpec: step.experimentSpec,
                experimentDecision: step.experimentDecision,
                experimentCandidateID: step.experimentCandidateID,
                experimentSandboxPath: step.experimentSandboxPath,
                selectedExperimentCandidate: step.selectedExperimentCandidate,
                experimentOutcome: step.experimentOutcome,
                knowledgeTier: step.knowledgeTier,
                notes: ["mixed-task OS handoff"] + step.notes,
                recoveryTagged: step.recoveryTagged,
                recoveryStrategy: step.recoveryStrategy,
                recoverySource: step.recoverySource
            )
        }

        guard let codeStep = codePlanner.nextStep(
            taskContext: taskContext,
            worldState: worldState,
            graphStore: graphStore,
            memoryStore: memoryStore,
            selectedStrategy: selectedStrategy
        ) else {
            return nil
        }

        return PlannerDecision(
            agentKind: .code,
            skillName: codeStep.skillName,
            plannerFamily: .mixed,
            stepPhase: .engineering,
            executionMode: codeStep.executionMode,
            actionContract: codeStep.actionContract,
            source: codeStep.source,
            workflowID: codeStep.workflowID,
            workflowStepID: codeStep.workflowStepID,
            pathEdgeIDs: codeStep.pathEdgeIDs,
            currentEdgeID: codeStep.currentEdgeID,
            fallbackReason: codeStep.fallbackReason,
            graphSearchDiagnostics: codeStep.graphSearchDiagnostics,
            semanticQuery: codeStep.semanticQuery,
            projectMemoryRefs: codeStep.projectMemoryRefs,
            architectureFindings: codeStep.architectureFindings,
            refactorProposalID: codeStep.refactorProposalID,
            experimentSpec: codeStep.experimentSpec,
            experimentDecision: codeStep.experimentDecision,
            experimentCandidateID: codeStep.experimentCandidateID,
            experimentSandboxPath: codeStep.experimentSandboxPath,
            selectedExperimentCandidate: codeStep.selectedExperimentCandidate,
            experimentOutcome: codeStep.experimentOutcome,
            knowledgeTier: codeStep.knowledgeTier,
            notes: ["mixed-task code handoff"] + codeStep.notes,
            recoveryTagged: codeStep.recoveryTagged,
            recoveryStrategy: codeStep.recoveryStrategy,
            recoverySource: codeStep.recoverySource
        )
    }
}
