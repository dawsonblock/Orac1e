import Foundation

public final class GitStatusSkill: CodeSkill {
    public let name = "git_status"

    public init() {}

    public func resolve(
        taskContext: TaskContext,
        state: WorldState,
memoryStore _: UnifiedMemoryStore
    ) throws -> SkillResolution {
        let workspaceRoot = try CodeSkillSupport.workspaceRoot(taskContext: taskContext, state: state)
        let snapshot = try CodeSkillSupport.repositorySnapshot(state: state, workspaceRoot: workspaceRoot)
        let command = CodeSkillSupport.command(
            category: .gitStatus,
            workspaceRoot: workspaceRoot,
            summary: "git status --short",
            arguments: ["git", "status", "--short"]
        )
        return SkillResolution(intent: .code(name: "Git status", command: command), repositorySnapshotID: snapshot.id)
    }
}
