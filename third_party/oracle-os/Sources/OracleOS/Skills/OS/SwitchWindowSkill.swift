import Foundation

public final class SwitchWindowSkill: Skill {
    public let name = "switch_window"

    public init() {}

    public func resolve(
        query: ElementQuery,
        state: WorldState,
        memoryStore _: UnifiedMemoryStore
    ) throws -> SkillResolution {
        let appName = query.app ?? state.observation.app ?? "unknown"
        let intent = ActionIntent.focus(
            app: appName,
            windowTitle: query.text
        )
        return SkillResolution(intent: intent, semanticQuery: query)
    }
}
