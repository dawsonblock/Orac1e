import Foundation

public final class SearchCodeSkill: CodeSkill {
    public let name = "search_code"

    public init() {}

    public func resolve(
        taskContext: TaskContext,
        state: WorldState,
memoryStore _: UnifiedMemoryStore
    ) throws -> SkillResolution {
        let workspaceRoot = try CodeSkillSupport.workspaceRoot(taskContext: taskContext, state: state)
        let snapshot = try CodeSkillSupport.repositorySnapshot(state: state, workspaceRoot: workspaceRoot)
        let query = taskContext.goal.description
        let command = CodeSkillSupport.command(
            category: .searchCode,
            workspaceRoot: workspaceRoot,
            summary: "search code for \(query)"
        )
        return SkillResolution(
            intent: .code(name: "Search code", command: command, text: query),
            repositorySnapshotID: snapshot.id
        )
    }
}
