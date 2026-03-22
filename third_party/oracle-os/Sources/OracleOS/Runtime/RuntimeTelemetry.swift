import Foundation

/// Handles telemetry, metrics, and trace recording for the runtime.
@MainActor
public struct RuntimeTelemetry {
    private let context: RuntimeContext

    public init(context: RuntimeContext) {
        self.context = context
    }

    /// Record a single action outcome in metrics.
    public func recordAction(
        success: Bool,
        elapsedMs: Double,
        isPatch: Bool
    ) {
        context.metricsRecorder.recordAction(
            success: success,
            elapsedMs: elapsedMs,
            isPatch: isPatch
        )
    }

    /// Record a full search cycle outcome in metrics.
    public func recordSearchCycle(
        candidatesGenerated: Int,
        memoryCandidates: Int,
        graphCandidates: Int,
        llmFallbackCandidates: Int
    ) {
        context.metricsRecorder.recordSearchCycle(
            candidatesGenerated: candidatesGenerated,
            memoryCandidates: memoryCandidates,
            graphCandidates: graphCandidates,
            llmFallbackCandidates: llmFallbackCandidates
        )
    }

    /// Create and record a trace event for a blocked or pending action.
    public func recordBlockedTrace(
        sessionID: String,
        taskID: String?,
        toolName: String?,
        intent: ActionIntent,
        policyDecision: PolicyDecision,
        approvalRequestID: String?,
        approvalStatus: String?,
        planningState: PlanningState,
        preHash: String,
        repositorySnapshot: RepositorySnapshot?,
        surface: RuntimeSurface,
        message: String
    ) -> URL? {
        let stepID = context.traceRecorder.makeStepID()
        
        let event = TraceEvent(
            sessionID: sessionID,
            taskID: taskID,
            stepID: stepID,
            toolName: toolName,
            actionName: intent.action,
            actionTarget: intent.targetQuery ?? intent.elementID,
            actionText: policyDecision.protectedOperation == .credentialEntry ? nil : intent.text,
            selectedElementID: intent.elementID,
            selectedElementLabel: nil,
            candidateScore: nil,
            candidateReasons: [],
            ambiguityScore: nil,
            preObservationHash: preHash,
            postObservationHash: preHash,
            planningStateID: planningState.id.rawValue,
            beliefSnapshotID: nil,
            postcondition: nil,
            postconditionClass: nil,
            actionContractID: nil,
            executionMode: "policy-\(approvalStatus == ApprovalStatus.pending.rawValue ? "pending" : "blocked")",
            plannerSource: nil,
            pathEdgeIDs: nil,
            currentEdgeID: nil,
            verified: false,
            success: false,
            failureClass: "policyBlocked",
            recoveryStrategy: nil,
            recoverySource: nil,
            recoveryTagged: nil,
            surface: surface.rawValue,
            policyMode: policyDecision.policyMode.rawValue,
            protectedOperation: policyDecision.protectedOperation?.rawValue,
            approvalRequestID: approvalRequestID,
            approvalOutcome: approvalStatus,
            blockedByPolicy: true,
            appProfile: policyDecision.appProtectionProfile.rawValue,
            agentKind: intent.agentKind.rawValue,
            domain: intent.domain,
            plannerFamily: nil,
            workspaceRelativePath: intent.workspaceRelativePath,
            commandCategory: intent.commandCategory,
            commandSummary: intent.commandSummary,
            repositorySnapshotID: repositorySnapshot?.id,
            buildResultSummary: nil,
            testResultSummary: nil,
            patchID: nil,
            projectMemoryRefs: nil,
            experimentID: nil,
            candidateID: nil,
            sandboxPath: nil,
            selectedCandidate: nil,
            experimentOutcome: nil,
            architectureFindings: nil,
            refactorProposalID: nil,
            knowledgeTier: nil,
            elapsedMs: 0,
            screenshotPath: nil,
            notes: message
        )

        context.traceRecorder.record(event)
        return try? context.traceStore.append(event)
    }
}
