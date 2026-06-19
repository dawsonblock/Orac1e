import Foundation

public struct ClickSkill: Skill {

    public let name = "click"

    public init() {}

    public func resolve(
        query: ElementQuery,
        state: WorldState,
        memoryStore: UnifiedMemoryStore
    ) throws -> SkillResolution {
        let best = try OSTargetResolver.resolve(
            query: query,
            state: state,
            memoryStore: memoryStore
        )

        let intent = ActionIntent.click(
            app: state.observation.app,
            query: best.element.label ?? query.text,
            role: best.element.role,
            domID: best.element.id
        )

        return SkillResolution(
            intent: intent,
            selectedCandidate: best,
            semanticQuery: query
        )
    }
}
