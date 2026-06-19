import Foundation

public final class ReadFileSkill: Skill {
    public let name = "read_file"

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

        let intent = ActionIntent(
            agentKind: .os,
            app: state.observation.app ?? "Finder",
            name: "read file \(candidate.element.label ?? query.text ?? "")",
            action: "read-file",
            query: candidate.element.label ?? query.text,
            role: candidate.element.role,
            domID: candidate.element.id
        )
        return SkillResolution(
            intent: intent,
            selectedCandidate: candidate,
            semanticQuery: query
        )
    }
}
