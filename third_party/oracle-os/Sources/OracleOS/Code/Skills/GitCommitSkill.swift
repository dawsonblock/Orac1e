import Foundation

public final class GitCommitSkill: CodeSkill {
    public let name = "git_commit"

    public init() {}

    public func resolve(
        taskContext: TaskContext,
        state: WorldState,
memoryStore _: UnifiedMemoryStore
    ) throws -> SkillResolution {
        let workspaceRoot = try CodeSkillSupport.workspaceRoot(taskContext: taskContext, state: state)
        let snapshot = try CodeSkillSupport.repositorySnapshot(state: state, workspaceRoot: workspaceRoot)
        let command = CodeSkillSupport.command(
            category: .gitCommit,
            workspaceRoot: workspaceRoot,
            summary: "git commit -am \"oracle automated change\"",
            arguments: ["git", "commit", "-am", "oracle automated change"]
        )
        return SkillResolution(intent: .code(name: "Git commit", command: command), repositorySnapshotID: snapshot.id)
    }
}
