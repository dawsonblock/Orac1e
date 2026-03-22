import Foundation

/// Aggregated context for strategy selection and plan generation.
///
/// ``PlanningContext`` is assembled from runtime state and passed to the
/// ``StrategySelector`` before any planning occurs. It captures every
/// signal needed to choose the right strategy.
public struct PlanningContext: Sendable {
    public let worldState: WorldState
    public let abstractStateSignature: String
    public let currentTaskRecordID: String?
    public let taskContext: TaskContext
    public let workflowMatches: [WorkflowMatcher.Match]
    public let memoryInfluence: MemoryInfluence
    public let recentFailureCount: Int
    public let agentKind: AgentKind

    // Strategy persistence fields
    public let currentStrategy: SelectedStrategy?
    public let strategyStartStep: Int
    public let stepsSinceSelection: Int

    public init(
        worldState: WorldState,
        abstractStateSignature: String = "",
        currentTaskRecordID: String? = nil,
        taskContext: TaskContext,
        workflowMatches: [WorkflowMatcher.Match] = [],
        memoryInfluence: MemoryInfluence = MemoryInfluence(),
        recentFailureCount: Int = 0,
        agentKind: AgentKind = .mixed,
        currentStrategy: SelectedStrategy? = nil,
        strategyStartStep: Int = 0,
        stepsSinceSelection: Int = 0
    ) {
        self.worldState = worldState
        self.abstractStateSignature = abstractStateSignature
        self.currentTaskRecordID = currentTaskRecordID
        self.taskContext = taskContext
        self.workflowMatches = workflowMatches
        self.memoryInfluence = memoryInfluence
        self.recentFailureCount = recentFailureCount
        self.agentKind = agentKind
        self.currentStrategy = currentStrategy
        self.strategyStartStep = strategyStartStep
        self.stepsSinceSelection = stepsSinceSelection
    }
}
