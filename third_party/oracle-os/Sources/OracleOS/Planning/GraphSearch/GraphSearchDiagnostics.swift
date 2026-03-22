import Foundation

public struct GraphSearchDiagnostics: Sendable, Codable, Equatable {
    public let exploredStateIDs: [String]
    public let exploredEdgeIDs: [String]
    public let chosenPathEdgeIDs: [String]
    public let rejectedEdgeIDs: [String]
    public let fallbackReason: String?
    /// Number of times the search detected a cycle (edge targeting an already-visited state).
    public let cycleDetections: Int

    public init(
        exploredStateIDs: [String] = [],
        exploredEdgeIDs: [String] = [],
        chosenPathEdgeIDs: [String] = [],
        rejectedEdgeIDs: [String] = [],
        fallbackReason: String? = nil,
        cycleDetections: Int = 0
    ) {
        self.exploredStateIDs = exploredStateIDs
        self.exploredEdgeIDs = exploredEdgeIDs
        self.chosenPathEdgeIDs = chosenPathEdgeIDs
        self.rejectedEdgeIDs = rejectedEdgeIDs
        self.fallbackReason = fallbackReason
        self.cycleDetections = cycleDetections
    }
}

public struct GraphEdgeSelection: Sendable {
    public let edge: EdgeTransition
    public let actionContract: ActionContract?
    public let source: PlannerSource
    public let score: Double
    public let diagnostics: GraphSearchDiagnostics

    public init(
        edge: EdgeTransition,
        actionContract: ActionContract?,
        source: PlannerSource,
        score: Double,
        diagnostics: GraphSearchDiagnostics
    ) {
        self.edge = edge
        self.actionContract = actionContract
        self.source = source
        self.score = score
        self.diagnostics = diagnostics
    }
}
