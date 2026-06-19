import Foundation

public struct ActionResult: Sendable, Codable {
    public let success: Bool
    public let verified: Bool
    public let message: String?
    public let method: String?
    public let verificationStatus: VerificationStatus?
    public let failureClass: String?
    public let elapsedMs: Double
    public let policyDecision: PolicyDecision?
    public let protectedOperation: String?
    public let approvalRequestID: String?
    public let approvalStatus: String?
    public let surface: String?
    public let appProtectionProfile: String?
    public let blockedByPolicy: Bool

    /// True when the action was executed through ``VerifiedExecutor``.
    /// Every action in the runtime loop must pass through the executor;
    /// consuming code can assert this flag to enforce the trust boundary.
    public let executedThroughExecutor: Bool

    public init(
        success: Bool,
        verified: Bool? = nil,
        message: String? = nil,
        method: String? = nil,
        verificationStatus: VerificationStatus? = nil,
        failureClass: String? = nil,
        elapsedMs: Double = 0,
        policyDecision: PolicyDecision? = nil,
        protectedOperation: String? = nil,
        approvalRequestID: String? = nil,
        approvalStatus: String? = nil,
        surface: String? = nil,
        appProtectionProfile: String? = nil,
        blockedByPolicy: Bool = false,
        executedThroughExecutor: Bool = false
    ) {
        self.success = success
        self.verified = verified ?? success
        self.message = message
        self.method = method
        self.verificationStatus = verificationStatus
        self.failureClass = failureClass
        self.elapsedMs = elapsedMs
        self.policyDecision = policyDecision
        self.protectedOperation = protectedOperation
        self.approvalRequestID = approvalRequestID
        self.approvalStatus = approvalStatus
        self.surface = surface
        self.appProtectionProfile = appProtectionProfile
        self.blockedByPolicy = blockedByPolicy
        self.executedThroughExecutor = executedThroughExecutor
    }

    enum CodingKeys: String, CodingKey {
        case success
        case verified
        case message
        case method
        case verificationStatus = "verification_status"
        case failureClass = "failure_class"
        case elapsedMs = "elapsed_ms"
        case policyDecision = "policy_decision"
        case protectedOperation = "protected_operation"
        case approvalRequestID = "approval_request_id"
        case approvalStatus = "approval_status"
        case surface
        case appProtectionProfile = "app_protection_profile"
        case blockedByPolicy = "blocked_by_policy"
        case executedThroughExecutor = "executed_through_executor"
    }

    public func toDict() -> [String: Any] {
        (try? ToolResultCoder.encode(self)) ?? [:]
    }

    public static func from(dict: [String: Any]) -> ActionResult? {
        ToolResultCoder.decode(ActionResult.self, from: dict)
    }
}

public struct TraceResult: Sendable, Codable, Equatable {
    public let cycleID: String?
    public let intentID: String?
    public let snapshotID: String?
    public let sessionID: String?
    public let stepID: Int?
    public let agentKind: String?
    public let plannerFamily: String?
    public let commandCategory: String?
    public let commandSummary: String?
    public let workspaceRelativePath: String?

    public init(
        cycleID: String? = nil,
        intentID: String? = nil,
        snapshotID: String? = nil,
        sessionID: String? = nil,
        stepID: Int? = nil,
        agentKind: String? = nil,
        plannerFamily: String? = nil,
        commandCategory: String? = nil,
        commandSummary: String? = nil,
        workspaceRelativePath: String? = nil
    ) {
        self.cycleID = cycleID
        self.intentID = intentID
        self.snapshotID = snapshotID
        self.sessionID = sessionID
        self.stepID = stepID
        self.agentKind = agentKind
        self.plannerFamily = plannerFamily
        self.commandCategory = commandCategory
        self.commandSummary = commandSummary
        self.workspaceRelativePath = workspaceRelativePath
    }

    enum CodingKeys: String, CodingKey {
        case cycleID = "cycle_id"
        case intentID = "intent_id"
        case snapshotID = "snapshot_id"
        case sessionID = "session_id"
        case stepID = "step_id"
        case agentKind = "agent_kind"
        case plannerFamily = "planner_family"
        case commandCategory = "command_category"
        case commandSummary = "command_summary"
        case workspaceRelativePath = "workspace_relative_path"
    }

    public static func from(dict: [String: Any]) -> TraceResult? {
        ToolResultCoder.decode(TraceResult.self, from: dict)
    }
}

public struct CodeExecutionResult: Sendable, Codable, Equatable {
    public let commandCategory: String?
    public let summary: String?
    public let workspaceRelativePath: String?
    public let buildResultSummary: String?
    public let testResultSummary: String?
    public let patchID: String?

    public init(
        commandCategory: String? = nil,
        summary: String? = nil,
        workspaceRelativePath: String? = nil,
        buildResultSummary: String? = nil,
        testResultSummary: String? = nil,
        patchID: String? = nil
    ) {
        self.commandCategory = commandCategory
        self.summary = summary
        self.workspaceRelativePath = workspaceRelativePath
        self.buildResultSummary = buildResultSummary
        self.testResultSummary = testResultSummary
        self.patchID = patchID
    }

    enum CodingKeys: String, CodingKey {
        case commandCategory = "command_category"
        case summary
        case workspaceRelativePath = "workspace_relative_path"
        case buildResultSummary = "build_result_summary"
        case testResultSummary = "test_result_summary"
        case patchID = "patch_id"
    }

    public static func from(dict: [String: Any]) -> CodeExecutionResult? {
        ToolResultCoder.decode(CodeExecutionResult.self, from: dict)
    }
}

public struct RecipeStepBoundaryResult: Sendable, Codable, Equatable {
    public let step: Int
    public let action: String
    public let success: Bool
    public let durationMs: Int
    public let error: String?
    public let note: String?

    public init(step: Int, action: String, success: Bool, durationMs: Int, error: String? = nil, note: String? = nil) {
        self.step = step
        self.action = action
        self.success = success
        self.durationMs = durationMs
        self.error = error
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case step
        case action
        case success
        case durationMs = "duration_ms"
        case error
        case note
    }
}

public struct RecipeRunBoundaryResult: Sendable, Codable, Equatable {
    public let recipe: String
    public let stepsCompleted: Int
    public let totalSteps: Int
    public let durationMs: Int?
    public let failedStep: Int?
    public let failedAction: String?
    public let failedNote: String?
    public let pendingApproval: Bool
    public let approvalRequestID: String?
    public let resumeToken: String?
    public let currentContext: [String: JSONValue]?
    public let stepResults: [RecipeStepBoundaryResult]

    public init(
        recipe: String,
        stepsCompleted: Int,
        totalSteps: Int,
        durationMs: Int? = nil,
        failedStep: Int? = nil,
        failedAction: String? = nil,
        failedNote: String? = nil,
        pendingApproval: Bool = false,
        approvalRequestID: String? = nil,
        resumeToken: String? = nil,
        currentContext: [String: JSONValue]? = nil,
        stepResults: [RecipeStepBoundaryResult]
    ) {
        self.recipe = recipe
        self.stepsCompleted = stepsCompleted
        self.totalSteps = totalSteps
        self.durationMs = durationMs
        self.failedStep = failedStep
        self.failedAction = failedAction
        self.failedNote = failedNote
        self.pendingApproval = pendingApproval
        self.approvalRequestID = approvalRequestID
        self.resumeToken = resumeToken
        self.currentContext = currentContext
        self.stepResults = stepResults
    }

    enum CodingKeys: String, CodingKey {
        case recipe
        case stepsCompleted = "steps_completed"
        case totalSteps = "total_steps"
        case durationMs = "duration_ms"
        case failedStep = "failed_step"
        case failedAction = "failed_action"
        case failedNote = "failed_note"
        case pendingApproval = "pending_approval"
        case approvalRequestID = "approval_request_id"
        case resumeToken = "resume_token"
        case currentContext = "current_context"
        case stepResults = "step_results"
    }

    public static func from(dict: [String: Any]) -> RecipeRunBoundaryResult? {
        ToolResultCoder.decode(RecipeRunBoundaryResult.self, from: dict)
    }
}

public struct RuntimeBoundaryResult: Sendable, Codable {
    public let summary: String
    public let method: String
    public let actionResult: ActionResult
    public let trace: TraceResult?
    public let codeExecution: CodeExecutionResult?
    public let recipeRun: RecipeRunBoundaryResult?

    public init(
        summary: String,
        method: String,
        actionResult: ActionResult,
        trace: TraceResult? = nil,
        codeExecution: CodeExecutionResult? = nil,
        recipeRun: RecipeRunBoundaryResult? = nil
    ) {
        self.summary = summary
        self.method = method
        self.actionResult = actionResult
        self.trace = trace
        self.codeExecution = codeExecution
        self.recipeRun = recipeRun
    }

    enum CodingKeys: String, CodingKey {
        case summary
        case method
        case actionResult = "action_result"
        case trace
        case codeExecution = "code_execution"
        case recipeRun = "recipe_run"
    }

    public static func from(dict: [String: Any]) -> RuntimeBoundaryResult? {
        ToolResultCoder.decode(RuntimeBoundaryResult.self, from: dict)
    }
}
