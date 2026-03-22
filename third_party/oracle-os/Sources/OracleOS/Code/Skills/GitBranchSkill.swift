import Foundation

public final class GitBranchSkill: CodeSkill {
    public let name = "git_branch"

    public init() {}

    public func resolve(
        taskContext: TaskContext,
        state: WorldState,
memoryStore _: UnifiedMemoryStore
    ) throws -> SkillResolution {
        let workspaceRoot = try CodeSkillSupport.workspaceRoot(taskContext: taskContext, state: state)
        let snapshot = try CodeSkillSupport.repositorySnapshot(state: state, workspaceRoot: workspaceRoot)
        let branchName = "oracle-\(UUID().uuidString.prefix(8))"
        let command = CodeSkillSupport.command(
            category: .gitBranch,
            workspaceRoot: workspaceRoot,
            summary: "git checkout -b \(branchName)",
            arguments: ["git", "checkout", "-b", branchName]
        )
        return SkillResolution(intent: .code(name: "Create branch", command: command), repositorySnapshotID: snapshot.id)
    }
}
