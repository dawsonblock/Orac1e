import Foundation

public final class TypeSkill: Skill {
    public let name = "type"

    public init() {}

    public func resolve(
        query: ElementQuery,
        state: WorldState,
        memoryStore: UnifiedMemoryStore
    ) throws -> SkillResolution {
        let candidate = try OSTargetResolver.resolve(
            query: query,
            state: state,
            memoryStore: memoryStore
        )
        let intent = ActionIntent.type(
            app: state.observation.app,
            into: candidate.element.label ?? query.text,
            domID: candidate.element.id,
            text: query.text ?? ""
        )
        return SkillResolution(intent: intent, selectedCandidate: candidate, semanticQuery: query)
    }
}
