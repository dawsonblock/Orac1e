import Foundation

public final class GitPushSkill: CodeSkill {
    public let name = "git_push"

    public init() {}

    public func resolve(
        taskContext: TaskContext,
        state: WorldState,
memoryStore _: UnifiedMemoryStore
    ) throws -> SkillResolution {
        let workspaceRoot = try CodeSkillSupport.workspaceRoot(taskContext: taskContext, state: state)
        let snapshot = try CodeSkillSupport.repositorySnapshot(state: state, workspaceRoot: workspaceRoot)
        let command = CodeSkillSupport.command(
            category: .gitPush,
            workspaceRoot: workspaceRoot,
            summary: "git push origin HEAD",
            arguments: ["git", "push", "origin", "HEAD"],
            touchesNetwork: true
        )
        return SkillResolution(intent: .code(name: "Git push", command: command), repositorySnapshotID: snapshot.id)
    }
}
