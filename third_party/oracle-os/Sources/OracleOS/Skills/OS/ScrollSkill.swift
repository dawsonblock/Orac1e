import Foundation

public final class ScrollSkill: Skill {
    public let name = "scroll"

    public init() {}

    public func resolve(
        query: ElementQuery,
        state: WorldState,
        memoryStore _: UnifiedMemoryStore
    ) throws -> SkillResolution {
        let intent = ActionIntent(
            agentKind: .os,
            app: state.observation.app ?? query.app ?? "unknown",
            name: "scroll \(query.text ?? "down")",
            action: "scroll",
            query: query.text
        )
        return SkillResolution(intent: intent, semanticQuery: query)
    }
}
