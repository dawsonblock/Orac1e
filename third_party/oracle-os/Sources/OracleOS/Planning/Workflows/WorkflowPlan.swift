import Foundation

public enum WorkflowPromotionStatus: String, Codable, Sendable, CaseIterable {
    case candidate
    case promoted
    case rejected
    case stale
}

public struct WorkflowStep: Sendable, Identifiable {
    public let id: String
    public let agentKind: AgentKind
    public let stepPhase: TaskStepPhase
    public let actionContract: ActionContract
    public let semanticQuery: ElementQuery?
    public let fromPlanningStateID: String?
    public let notes: [String]

    public init(
        id: String = UUID().uuidString,
        agentKind: AgentKind,
        stepPhase: TaskStepPhase,
        actionContract: ActionContract,
        semanticQuery: ElementQuery? = nil,
        fromPlanningStateID: String? = nil,
        notes: [String] = []
    ) {
        self.id = id
        self.agentKind = agentKind
        self.stepPhase = stepPhase
        self.actionContract = actionContract
        self.semanticQuery = semanticQuery
        self.fromPlanningStateID = fromPlanningStateID
        self.notes = notes
    }
}

public struct WorkflowPlan: Sendable, Identifiable {
    public let id: String
    public let agentKind: AgentKind
    public let goalPattern: String
    public let steps: [WorkflowStep]
    public let parameterSlots: [String]
    public let parameterKinds: [String: String]
    public let parameterExamples: [String: [String]]
    public let successRate: Double
    public let sourceTraceRefs: [String]
    public let sourceGraphEdgeRefs: [String]
    public let evidenceTiers: [KnowledgeTier]
    public let repeatedTraceSegmentCount: Int
    public let replayValidationSuccess: Double
    public let promotionStatus: WorkflowPromotionStatus
    public let lastValidatedAt: Date?
    public let lastSucceededAt: Date?

    public init(
        id: String = UUID().uuidString,
        agentKind: AgentKind,
        goalPattern: String,
        steps: [WorkflowStep],
        parameterSlots: [String] = [],
        parameterKinds: [String: String] = [:],
        parameterExamples: [String: [String]] = [:],
        successRate: Double,
        sourceTraceRefs: [String] = [],
        sourceGraphEdgeRefs: [String] = [],
        evidenceTiers: [KnowledgeTier] = [.candidate],
        repeatedTraceSegmentCount: Int = 0,
        replayValidationSuccess: Double = 0,
        promotionStatus: WorkflowPromotionStatus = .candidate,
        lastValidatedAt: Date? = nil,
        lastSucceededAt: Date? = nil
    ) {
        self.id = id
        self.agentKind = agentKind
        self.goalPattern = goalPattern
        self.steps = steps
        self.parameterSlots = parameterSlots
        self.parameterKinds = parameterKinds
        self.parameterExamples = parameterExamples
        self.successRate = successRate
        self.sourceTraceRefs = sourceTraceRefs
        self.sourceGraphEdgeRefs = sourceGraphEdgeRefs
        self.evidenceTiers = evidenceTiers
        self.repeatedTraceSegmentCount = repeatedTraceSegmentCount
        self.replayValidationSuccess = replayValidationSuccess
        self.promotionStatus = promotionStatus
        self.lastValidatedAt = lastValidatedAt
        self.lastSucceededAt = lastSucceededAt
    }
}
