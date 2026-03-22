import Foundation

public final class ReadRepositorySkill: CodeSkill {
    public let name = "read_repository"

    public init() {}

    public func resolve(
        taskContext: TaskContext,
        state: WorldState,
memoryStore _: UnifiedMemoryStore
    ) throws -> SkillResolution {
        let workspaceRoot = try CodeSkillSupport.workspaceRoot(taskContext: taskContext, state: state)
        let snapshot = try CodeSkillSupport.repositorySnapshot(state: state, workspaceRoot: workspaceRoot)
        let command = CodeSkillSupport.command(
            category: .indexRepository,
            workspaceRoot: workspaceRoot,
            summary: "index repository"
        )
        return SkillResolution(
            intent: .code(name: "Index repository", command: command),
            repositorySnapshotID: snapshot.id
        )
    }
}
