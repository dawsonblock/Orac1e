import Foundation

public final class EditFileSkill: CodeSkill {
    public let name = "edit_file"

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
            category: .editFile,
            workspaceRoot: workspaceRoot,
            workspaceRelativePath: path,
            summary: "edit \(path)"
        )
        return SkillResolution(
            intent: .code(name: "Edit file", command: command, workspaceRelativePath: path),
            repositorySnapshotID: snapshot.id
        )
    }
}
