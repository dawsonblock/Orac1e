import Foundation

/// A single trace event capturing one verified execution step.
///
/// Trace events store **verified deltas** — action proposals, authorized
/// actions, executor results, verification outcomes, and committed state
/// deltas.  Large raw observations (full AX trees, DOM snapshots, filesystem
/// dumps) are excluded from normal traces and stored only in debug mode.
///
/// Fields retained in normal traces:
/// - action proposal and authorization
/// - executor result and verification status
/// - committed state delta (observation hashes, planning state IDs)
/// - timestamps and action-specific evidence
public struct TraceEvent: Codable, Sendable {
    public let schemaVersion: Int
    public let sessionID: String
    public let taskID: String?
    public let stepID: Int
    public let timestamp: Date

    public let toolName: String?
    public let actionName: String
    public let actionTarget: String?
    public let actionText: String?

    public let selectedElementID: String?
    public let selectedElementLabel: String?
    public let candidateScore: Double?
    public let candidateReasons: [String]
    public let ambiguityScore: Double?

    public let preObservationHash: String?
    public let postObservationHash: String?
    public let planningStateID: String?
    public let beliefSnapshotID: String?

    public let postcondition: String?
    public let postconditionClass: String?
    public let actionContractID: String?
    public let executionMode: String?
    public let plannerSource: String?
    public let pathEdgeIDs: [String]?
    public let currentEdgeID: String?
    public let verified: Bool
    public let success: Bool
    public let failureClass: String?
    public let recoveryStrategy: String?
    public let recoverySource: String?
    public let recoveryTagged: Bool?
    public let surface: String?
    public let policyMode: String?
    public let protectedOperation: String?
    public let approvalRequestID: String?
    public let approvalOutcome: String?
    public let blockedByPolicy: Bool?
    public let appProfile: String?
    public let agentKind: String?
    public let domain: String?
    public let plannerFamily: String?
    public let workspaceRelativePath: String?
    public let commandCategory: String?
    public let commandSummary: String?
    public let repositorySnapshotID: String?
    public let buildResultSummary: String?
    public let testResultSummary: String?
    public let patchID: String?
    public let projectMemoryRefs: [String]?
    public let experimentID: String?
    public let candidateID: String?
    public let sandboxPath: String?
    public let selectedCandidate: Bool?
    public let experimentOutcome: String?
    public let architectureFindings: [String]?
    public let refactorProposalID: String?
    public let knowledgeTier: String?

    public let elapsedMs: Double
    public let screenshotPath: String?
    public let notes: String?

    public init(
        schemaVersion: Int = TraceSchemaVersion.current,
        sessionID: String,
        taskID: String?,
        stepID: Int,
        toolName: String?,
        actionName: String,
        actionTarget: String? = nil,
        actionText: String? = nil,
        selectedElementID: String? = nil,
        selectedElementLabel: String? = nil,
        candidateScore: Double? = nil,
        candidateReasons: [String] = [],
        ambiguityScore: Double? = nil,
        preObservationHash: String? = nil,
        postObservationHash: String? = nil,
        planningStateID: String? = nil,
        beliefSnapshotID: String? = nil,
        postcondition: String? = nil,
        postconditionClass: String? = nil,
        actionContractID: String? = nil,
        executionMode: String? = nil,
        plannerSource: String? = nil,
        pathEdgeIDs: [String]? = nil,
        currentEdgeID: String? = nil,
        verified: Bool,
        success: Bool,
        failureClass: String? = nil,
        recoveryStrategy: String? = nil,
        recoverySource: String? = nil,
        recoveryTagged: Bool? = nil,
        surface: String? = nil,
        policyMode: String? = nil,
        protectedOperation: String? = nil,
        approvalRequestID: String? = nil,
        approvalOutcome: String? = nil,
        blockedByPolicy: Bool? = nil,
        appProfile: String? = nil,
        agentKind: String? = nil,
        domain: String? = nil,
        plannerFamily: String? = nil,
        workspaceRelativePath: String? = nil,
        commandCategory: String? = nil,
        commandSummary: String? = nil,
        repositorySnapshotID: String? = nil,
        buildResultSummary: String? = nil,
        testResultSummary: String? = nil,
        patchID: String? = nil,
        projectMemoryRefs: [String]? = nil,
        experimentID: String? = nil,
        candidateID: String? = nil,
        sandboxPath: String? = nil,
        selectedCandidate: Bool? = nil,
        experimentOutcome: String? = nil,
        architectureFindings: [String]? = nil,
        refactorProposalID: String? = nil,
        knowledgeTier: String? = nil,
        elapsedMs: Double,
        screenshotPath: String? = nil,
        notes: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.taskID = taskID
        self.stepID = stepID
        self.timestamp = Date()
        self.toolName = toolName
        self.actionName = actionName
        self.actionTarget = actionTarget
        self.actionText = actionText
        self.selectedElementID = selectedElementID
        self.selectedElementLabel = selectedElementLabel
        self.candidateScore = candidateScore
        self.candidateReasons = candidateReasons
        self.ambiguityScore = ambiguityScore
        self.preObservationHash = preObservationHash
        self.postObservationHash = postObservationHash
        self.planningStateID = planningStateID
        self.beliefSnapshotID = beliefSnapshotID
        self.postcondition = postcondition
        self.postconditionClass = postconditionClass
        self.actionContractID = actionContractID
        self.executionMode = executionMode
        self.plannerSource = plannerSource
        self.pathEdgeIDs = pathEdgeIDs
        self.currentEdgeID = currentEdgeID
        self.verified = verified
        self.success = success
        self.failureClass = failureClass
        self.recoveryStrategy = recoveryStrategy
        self.recoverySource = recoverySource
        self.recoveryTagged = recoveryTagged
        self.surface = surface
        self.policyMode = policyMode
        self.protectedOperation = protectedOperation
        self.approvalRequestID = approvalRequestID
        self.approvalOutcome = approvalOutcome
        self.blockedByPolicy = blockedByPolicy
        self.appProfile = appProfile
        self.agentKind = agentKind
        self.domain = domain
        self.plannerFamily = plannerFamily
        self.workspaceRelativePath = workspaceRelativePath
        self.commandCategory = commandCategory
        self.commandSummary = commandSummary
        self.repositorySnapshotID = repositorySnapshotID
        self.buildResultSummary = buildResultSummary
        self.testResultSummary = testResultSummary
        self.patchID = patchID
        self.projectMemoryRefs = projectMemoryRefs
        self.experimentID = experimentID
        self.candidateID = candidateID
        self.sandboxPath = sandboxPath
        self.selectedCandidate = selectedCandidate
        self.experimentOutcome = experimentOutcome
        self.architectureFindings = architectureFindings
        self.refactorProposalID = refactorProposalID
        self.knowledgeTier = knowledgeTier
        self.elapsedMs = elapsedMs
        self.screenshotPath = screenshotPath
        self.notes = notes
    }

    public init(action: String, success: Bool, message: String? = nil) {
        self.init(
            schemaVersion: TraceSchemaVersion.current,
            sessionID: "compat",
            taskID: nil,
            stepID: 0,
            toolName: nil,
            actionName: action,
            actionTarget: nil,
            actionText: nil,
            selectedElementID: nil,
            selectedElementLabel: nil,
            candidateScore: nil,
            candidateReasons: [],
            ambiguityScore: nil,
            preObservationHash: nil,
            postObservationHash: nil,
            planningStateID: nil,
            beliefSnapshotID: nil,
            postcondition: nil,
            postconditionClass: nil,
            actionContractID: nil,
            executionMode: "compat",
            plannerSource: nil,
            pathEdgeIDs: nil,
            currentEdgeID: nil,
            verified: success,
            success: success,
            failureClass: success ? nil : "compat_failure",
            recoveryStrategy: nil,
            recoverySource: nil,
            recoveryTagged: nil,
            surface: nil,
            policyMode: nil,
            protectedOperation: nil,
            approvalRequestID: nil,
            approvalOutcome: nil,
            blockedByPolicy: nil,
            appProfile: nil,
            agentKind: nil,
            domain: nil,
            plannerFamily: nil,
            workspaceRelativePath: nil,
            commandCategory: nil,
            commandSummary: nil,
            repositorySnapshotID: nil,
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
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case sessionID
        case taskID
        case stepID
        case timestamp
        case toolName
        case actionName
        case actionTarget
        case actionText
        case selectedElementID
        case selectedElementLabel
        case candidateScore
        case candidateReasons
        case ambiguityScore
        case preObservationHash
        case postObservationHash
        case planningStateID
        case beliefSnapshotID
        case postcondition
        case postconditionClass
        case actionContractID
        case executionMode
        case plannerSource
        case pathEdgeIDs
        case currentEdgeID
        case verified
        case success
        case failureClass
        case recoveryStrategy
        case recoverySource
        case recoveryTagged
        case surface
        case policyMode
        case protectedOperation
        case approvalRequestID
        case approvalOutcome
        case blockedByPolicy
        case appProfile
        case agentKind
        case domain
        case plannerFamily
        case workspaceRelativePath
        case commandCategory
        case commandSummary
        case repositorySnapshotID
        case buildResultSummary
        case testResultSummary
        case patchID
        case projectMemoryRefs
        case experimentID
        case candidateID
        case sandboxPath
        case selectedCandidate
        case experimentOutcome
        case architectureFindings
        case refactorProposalID
        case knowledgeTier
        case elapsedMs
        case screenshotPath
        case notes

        // Legacy keys
        case action
        case message
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? false
        let decodedActionName = try container.decodeIfPresent(String.self, forKey: .actionName)
        let legacyActionName = try container.decodeIfPresent(String.self, forKey: .action)
        let decodedNotes = try container.decodeIfPresent(String.self, forKey: .notes)
        let legacyMessage = try container.decodeIfPresent(String.self, forKey: .message)

        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID) ?? "legacy"
        self.taskID = try container.decodeIfPresent(String.self, forKey: .taskID)
        self.stepID = try container.decodeIfPresent(Int.self, forKey: .stepID) ?? 0
        self.timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date(timeIntervalSince1970: 0)
        self.toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        self.actionName = decodedActionName ?? legacyActionName ?? "unknown"
        self.actionTarget = try container.decodeIfPresent(String.self, forKey: .actionTarget)
        self.actionText = try container.decodeIfPresent(String.self, forKey: .actionText)
        self.selectedElementID = try container.decodeIfPresent(String.self, forKey: .selectedElementID)
        self.selectedElementLabel = try container.decodeIfPresent(String.self, forKey: .selectedElementLabel)
        self.candidateScore = try container.decodeIfPresent(Double.self, forKey: .candidateScore)
        self.candidateReasons = try container.decodeIfPresent([String].self, forKey: .candidateReasons) ?? []
        self.ambiguityScore = try container.decodeIfPresent(Double.self, forKey: .ambiguityScore)
        self.preObservationHash = try container.decodeIfPresent(String.self, forKey: .preObservationHash)
        self.postObservationHash = try container.decodeIfPresent(String.self, forKey: .postObservationHash)
        self.planningStateID = try container.decodeIfPresent(String.self, forKey: .planningStateID)
        self.beliefSnapshotID = try container.decodeIfPresent(String.self, forKey: .beliefSnapshotID)
        self.postcondition = try container.decodeIfPresent(String.self, forKey: .postcondition)
        self.postconditionClass = try container.decodeIfPresent(String.self, forKey: .postconditionClass)
        self.actionContractID = try container.decodeIfPresent(String.self, forKey: .actionContractID)
        self.executionMode = try container.decodeIfPresent(String.self, forKey: .executionMode)
        self.plannerSource = try container.decodeIfPresent(String.self, forKey: .plannerSource)
        self.pathEdgeIDs = try container.decodeIfPresent([String].self, forKey: .pathEdgeIDs)
        self.currentEdgeID = try container.decodeIfPresent(String.self, forKey: .currentEdgeID)
        self.verified = try container.decodeIfPresent(Bool.self, forKey: .verified) ?? success
        self.success = success
        self.failureClass = try container.decodeIfPresent(String.self, forKey: .failureClass)
        self.recoveryStrategy = try container.decodeIfPresent(String.self, forKey: .recoveryStrategy)
        self.recoverySource = try container.decodeIfPresent(String.self, forKey: .recoverySource)
        self.recoveryTagged = try container.decodeIfPresent(Bool.self, forKey: .recoveryTagged)
        self.surface = try container.decodeIfPresent(String.self, forKey: .surface)
        self.policyMode = try container.decodeIfPresent(String.self, forKey: .policyMode)
        self.protectedOperation = try container.decodeIfPresent(String.self, forKey: .protectedOperation)
        self.approvalRequestID = try container.decodeIfPresent(String.self, forKey: .approvalRequestID)
        self.approvalOutcome = try container.decodeIfPresent(String.self, forKey: .approvalOutcome)
        self.blockedByPolicy = try container.decodeIfPresent(Bool.self, forKey: .blockedByPolicy)
        self.appProfile = try container.decodeIfPresent(String.self, forKey: .appProfile)
        self.agentKind = try container.decodeIfPresent(String.self, forKey: .agentKind)
        self.domain = try container.decodeIfPresent(String.self, forKey: .domain)
        self.plannerFamily = try container.decodeIfPresent(String.self, forKey: .plannerFamily)
        self.workspaceRelativePath = try container.decodeIfPresent(String.self, forKey: .workspaceRelativePath)
        self.commandCategory = try container.decodeIfPresent(String.self, forKey: .commandCategory)
        self.commandSummary = try container.decodeIfPresent(String.self, forKey: .commandSummary)
        self.repositorySnapshotID = try container.decodeIfPresent(String.self, forKey: .repositorySnapshotID)
        self.buildResultSummary = try container.decodeIfPresent(String.self, forKey: .buildResultSummary)
        self.testResultSummary = try container.decodeIfPresent(String.self, forKey: .testResultSummary)
        self.patchID = try container.decodeIfPresent(String.self, forKey: .patchID)
        self.projectMemoryRefs = try container.decodeIfPresent([String].self, forKey: .projectMemoryRefs)
        self.experimentID = try container.decodeIfPresent(String.self, forKey: .experimentID)
        self.candidateID = try container.decodeIfPresent(String.self, forKey: .candidateID)
        self.sandboxPath = try container.decodeIfPresent(String.self, forKey: .sandboxPath)
        self.selectedCandidate = try container.decodeIfPresent(Bool.self, forKey: .selectedCandidate)
        self.experimentOutcome = try container.decodeIfPresent(String.self, forKey: .experimentOutcome)
        self.architectureFindings = try container.decodeIfPresent([String].self, forKey: .architectureFindings)
        self.refactorProposalID = try container.decodeIfPresent(String.self, forKey: .refactorProposalID)
        self.knowledgeTier = try container.decodeIfPresent(String.self, forKey: .knowledgeTier)
        self.elapsedMs = try container.decodeIfPresent(Double.self, forKey: .elapsedMs) ?? 0
        self.screenshotPath = try container.decodeIfPresent(String.self, forKey: .screenshotPath)
        self.notes = decodedNotes ?? legacyMessage
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encodeIfPresent(taskID, forKey: .taskID)
        try container.encode(stepID, forKey: .stepID)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(toolName, forKey: .toolName)
        try container.encode(actionName, forKey: .actionName)
        try container.encodeIfPresent(actionTarget, forKey: .actionTarget)
        try container.encodeIfPresent(actionText, forKey: .actionText)
        try container.encodeIfPresent(selectedElementID, forKey: .selectedElementID)
        try container.encodeIfPresent(selectedElementLabel, forKey: .selectedElementLabel)
        try container.encodeIfPresent(candidateScore, forKey: .candidateScore)
        try container.encode(candidateReasons, forKey: .candidateReasons)
        try container.encodeIfPresent(ambiguityScore, forKey: .ambiguityScore)
        try container.encodeIfPresent(preObservationHash, forKey: .preObservationHash)
        try container.encodeIfPresent(postObservationHash, forKey: .postObservationHash)
        try container.encodeIfPresent(planningStateID, forKey: .planningStateID)
        try container.encodeIfPresent(beliefSnapshotID, forKey: .beliefSnapshotID)
        try container.encodeIfPresent(postcondition, forKey: .postcondition)
        try container.encodeIfPresent(postconditionClass, forKey: .postconditionClass)
        try container.encodeIfPresent(actionContractID, forKey: .actionContractID)
        try container.encodeIfPresent(executionMode, forKey: .executionMode)
        try container.encodeIfPresent(plannerSource, forKey: .plannerSource)
        try container.encodeIfPresent(pathEdgeIDs, forKey: .pathEdgeIDs)
        try container.encodeIfPresent(currentEdgeID, forKey: .currentEdgeID)
        try container.encode(verified, forKey: .verified)
        try container.encode(success, forKey: .success)
        try container.encodeIfPresent(failureClass, forKey: .failureClass)
        try container.encodeIfPresent(recoveryStrategy, forKey: .recoveryStrategy)
        try container.encodeIfPresent(recoverySource, forKey: .recoverySource)
        try container.encodeIfPresent(recoveryTagged, forKey: .recoveryTagged)
        try container.encodeIfPresent(surface, forKey: .surface)
        try container.encodeIfPresent(policyMode, forKey: .policyMode)
        try container.encodeIfPresent(protectedOperation, forKey: .protectedOperation)
        try container.encodeIfPresent(approvalRequestID, forKey: .approvalRequestID)
        try container.encodeIfPresent(approvalOutcome, forKey: .approvalOutcome)
        try container.encodeIfPresent(blockedByPolicy, forKey: .blockedByPolicy)
        try container.encodeIfPresent(appProfile, forKey: .appProfile)
        try container.encodeIfPresent(agentKind, forKey: .agentKind)
        try container.encodeIfPresent(domain, forKey: .domain)
        try container.encodeIfPresent(plannerFamily, forKey: .plannerFamily)
        try container.encodeIfPresent(workspaceRelativePath, forKey: .workspaceRelativePath)
        try container.encodeIfPresent(commandCategory, forKey: .commandCategory)
        try container.encodeIfPresent(commandSummary, forKey: .commandSummary)
        try container.encodeIfPresent(repositorySnapshotID, forKey: .repositorySnapshotID)
        try container.encodeIfPresent(buildResultSummary, forKey: .buildResultSummary)
        try container.encodeIfPresent(testResultSummary, forKey: .testResultSummary)
        try container.encodeIfPresent(patchID, forKey: .patchID)
        try container.encodeIfPresent(projectMemoryRefs, forKey: .projectMemoryRefs)
        try container.encodeIfPresent(experimentID, forKey: .experimentID)
        try container.encodeIfPresent(candidateID, forKey: .candidateID)
        try container.encodeIfPresent(sandboxPath, forKey: .sandboxPath)
        try container.encodeIfPresent(selectedCandidate, forKey: .selectedCandidate)
        try container.encodeIfPresent(experimentOutcome, forKey: .experimentOutcome)
        try container.encodeIfPresent(architectureFindings, forKey: .architectureFindings)
        try container.encodeIfPresent(refactorProposalID, forKey: .refactorProposalID)
        try container.encodeIfPresent(knowledgeTier, forKey: .knowledgeTier)
        try container.encode(elapsedMs, forKey: .elapsedMs)
        try container.encodeIfPresent(screenshotPath, forKey: .screenshotPath)
        try container.encodeIfPresent(notes, forKey: .notes)
    }
}
