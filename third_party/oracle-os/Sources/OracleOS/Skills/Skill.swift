import Foundation

public enum SkillResolutionError: Error, Sendable, Equatable {
    case noCandidate(String)
    case ambiguousTarget(String, Double)

    public var failureClass: FailureClass {
        switch self {
        case .noCandidate:
            return .elementNotFound
        case .ambiguousTarget:
            return .elementAmbiguous
        }
    }
}

public struct SkillResolution: Sendable {
    public let intent: ActionIntent
    public let selectedCandidate: ElementCandidate?
    public let semanticQuery: ElementQuery?
    public let repositorySnapshotID: String?

    public init(
        intent: ActionIntent,
        selectedCandidate: ElementCandidate? = nil,
        semanticQuery: ElementQuery? = nil,
        repositorySnapshotID: String? = nil
    ) {
        self.intent = intent
        self.selectedCandidate = selectedCandidate
        self.semanticQuery = semanticQuery
        self.repositorySnapshotID = repositorySnapshotID
    }
}

public protocol Skill {
    var name: String { get }

    func checkPreconditions(state: WorldState) -> Bool

    func resolve(
        query: ElementQuery,
        state: WorldState,
        memoryStore: UnifiedMemoryStore
    ) throws -> SkillResolution

    func buildProcedure(resolution: SkillResolution) -> [ActionIntent]

    func verify(state: WorldState, expectedDelta: StateDelta?) -> Bool

    func fallbacks(for failure: FailureClass) -> [ActionIntent]
}

public extension Skill {
    func checkPreconditions(state: WorldState) -> Bool { return true }
    func buildProcedure(resolution: SkillResolution) -> [ActionIntent] { return [resolution.intent] }
    func verify(state: WorldState, expectedDelta: StateDelta?) -> Bool { return true }
    func fallbacks(for failure: FailureClass) -> [ActionIntent] { return [] }
}

public protocol CodeSkill {
    var name: String { get }

    func checkPreconditions(state: WorldState) -> Bool

    func resolve(
        taskContext: TaskContext,
        state: WorldState,
        memoryStore: UnifiedMemoryStore
    ) throws -> SkillResolution
    
    func buildProcedure(resolution: SkillResolution) -> [ActionIntent]
    
    func verify(state: WorldState, expectedDelta: StateDelta?) -> Bool
    
    func fallbacks(for failure: FailureClass) -> [ActionIntent]
}

public extension CodeSkill {
    func checkPreconditions(state: WorldState) -> Bool { return true }
    func buildProcedure(resolution: SkillResolution) -> [ActionIntent] { return [resolution.intent] }
    func verify(state: WorldState, expectedDelta: StateDelta?) -> Bool { return true }
    func fallbacks(for failure: FailureClass) -> [ActionIntent] { return [] }
}
