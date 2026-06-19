import Foundation

public final class WriteFileSkill: CodeSkill {
    public let name = "write_file"

    public init() {}

    public func resolve(
        taskContext: TaskContext,
        state: WorldState,
memoryStore: UnifiedMemoryStore
    ) throws -> SkillResolution {
        let workspaceRoot = try CodeSkillSupport.workspaceRoot(taskContext: taskContext, state: state)
        let path = try CodeSkillSupport.preferredPath(taskContext: taskContext, state: state, memoryStore: memoryStore)
        let snapshot = try CodeSkillSupport.repositorySnapshot(state: state, workspaceRoot: workspaceRoot)
        let command = CodeSkillSupport.command(
            category: .writeFile,
            workspaceRoot: workspaceRoot,
            workspaceRelativePath: path,
            summary: "write \(path)"
        )
        return SkillResolution(
            intent: .code(name: "Write file", command: command, workspaceRelativePath: path, text: taskContext.goal.description),
            repositorySnapshotID: snapshot.id
        )
    }
}
