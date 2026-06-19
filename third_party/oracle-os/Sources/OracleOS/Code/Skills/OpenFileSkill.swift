import Foundation

public final class OpenFileSkill: CodeSkill {
    public let name = "open_file"

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
            category: .openFile,
            workspaceRoot: workspaceRoot,
            workspaceRelativePath: path,
            summary: "open \(path)"
        )
        return SkillResolution(
            intent: .code(name: "Open file", command: command, workspaceRelativePath: path),
            repositorySnapshotID: snapshot.id
        )
    }
}
