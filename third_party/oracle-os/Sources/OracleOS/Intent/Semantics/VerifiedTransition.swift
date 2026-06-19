import Foundation

public struct VerifiedTransition: Codable, Sendable {
    public let fromPlanningStateID: PlanningStateID
    public let toPlanningStateID: PlanningStateID
    public let actionContractID: String
    public let agentKind: AgentKind
    public let domain: String
    public let workspaceRelativePath: String?
    public let commandCategory: String?
    public let plannerFamily: String?
    public let postconditionClass: PostconditionClass
    public let verified: Bool
    public let failureClass: String?
    public let latencyMs: Int
    public let targetAmbiguityScore: Double?
    public let recoveryTagged: Bool
    public let approvalRequired: Bool
    public let approvalOutcome: String?
    public let knowledgeTier: KnowledgeTier
    public let timestamp: TimeInterval

    public init(
        fromPlanningStateID: PlanningStateID,
        toPlanningStateID: PlanningStateID,
        actionContractID: String,
        agentKind: AgentKind = .os,
        domain: String? = nil,
        workspaceRelativePath: String? = nil,
        commandCategory: String? = nil,
        plannerFamily: String? = nil,
        postconditionClass: PostconditionClass,
        verified: Bool,
        failureClass: String?,
        latencyMs: Int,
        targetAmbiguityScore: Double? = nil,
        recoveryTagged: Bool = false,
        approvalRequired: Bool = false,
        approvalOutcome: String? = nil,
        knowledgeTier: KnowledgeTier? = nil,
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.fromPlanningStateID = fromPlanningStateID
        self.toPlanningStateID = toPlanningStateID
        self.actionContractID = actionContractID
        self.agentKind = agentKind
        self.domain = domain ?? (agentKind == .code ? "code" : "os")
        self.workspaceRelativePath = workspaceRelativePath
        self.commandCategory = commandCategory
        self.plannerFamily = plannerFamily
        self.postconditionClass = postconditionClass
        self.verified = verified
        self.failureClass = failureClass
        self.latencyMs = latencyMs
        self.targetAmbiguityScore = targetAmbiguityScore
        self.recoveryTagged = recoveryTagged
        self.approvalRequired = approvalRequired
        self.approvalOutcome = approvalOutcome
        self.knowledgeTier = knowledgeTier ?? (recoveryTagged ? .recovery : .candidate)
        self.timestamp = timestamp
    }

    public func toDict() -> [String: Any] {
        [
            "from_planning_state_id": fromPlanningStateID.rawValue,
            "to_planning_state_id": toPlanningStateID.rawValue,
            "action_contract_id": actionContractID,
            "agent_kind": agentKind.rawValue,
            "domain": domain,
            "workspace_relative_path": workspaceRelativePath as Any,
            "command_category": commandCategory as Any,
            "planner_family": plannerFamily as Any,
            "postcondition_class": postconditionClass.rawValue,
            "verified": verified,
            "failure_class": failureClass as Any,
            "latency_ms": latencyMs,
            "target_ambiguity_score": targetAmbiguityScore as Any,
            "recovery_tagged": recoveryTagged,
            "approval_required": approvalRequired,
            "approval_outcome": approvalOutcome as Any,
            "knowledge_tier": knowledgeTier.rawValue,
            "timestamp": timestamp,
        ]
    }
}
