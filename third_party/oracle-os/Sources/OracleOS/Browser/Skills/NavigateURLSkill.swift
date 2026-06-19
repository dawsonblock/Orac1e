import Foundation

public final class NavigateURLSkill: Skill {
    public let name = "navigate_url"

    public init() {}

    public func resolve(
        query: ElementQuery,
        state: WorldState,
memoryStore _: UnifiedMemoryStore
    ) throws -> SkillResolution {
        let intent = ActionIntent(
            agentKind: .os,
            app: query.app ?? state.observation.app ?? "unknown",
            name: "navigate \(query.text ?? "")",
            action: "navigate-url",
            query: query.text
        )
        return SkillResolution(intent: intent, semanticQuery: query)
    }
}
