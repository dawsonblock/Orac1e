import Foundation

/// The sole planner contract.
/// INVARIANTS:
///   - Planners return Commands only.
///   - Planners must NOT execute, commit, write memory, or mutate state.
///   - Planners must NOT import Execution/Actions.
public protocol Planner: Sendable {
    func plan(intent: Intent, context: PlannerContext) async throws -> Command
}

public extension Planner {
    func plan(
        intent: Intent,
        state: WorldStateModel,
        repositorySnapshot: RepositorySnapshot? = nil
    ) async throws -> Command {
        try await plan(
            intent: intent,
            context: PlannerContext(state: state, repositorySnapshot: repositorySnapshot)
        )
    }
}

/// Lightweight planning context for the Planner protocol.
/// Distinct from Runtime/PlanningContext which serves strategy selection.
public struct PlannerContext: Sendable {
    public let state: WorldStateModel
    public let memories: [MemoryCandidate]
    public let repositorySnapshot: RepositorySnapshot?
    public init(state: WorldStateModel, memories: [MemoryCandidate] = [], repositorySnapshot: RepositorySnapshot? = nil) {
        self.state = state; self.memories = memories; self.repositorySnapshot = repositorySnapshot
    }
}

public struct MemoryCandidate: Sendable, Codable {
    public let id: UUID; public let content: String; public let confidence: Double; public let source: String
    public init(id: UUID = UUID(), content: String, confidence: Double, source: String) {
        self.id = id; self.content = content; self.confidence = confidence; self.source = source }
}
