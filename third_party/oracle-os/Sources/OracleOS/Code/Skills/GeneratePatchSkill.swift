import Foundation

public final class GeneratePatchSkill: CodeSkill {
    public let name = "generate_patch"

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
            category: .generatePatch,
            workspaceRoot: workspaceRoot,
            workspaceRelativePath: path,
            summary: "generate patch for \(path)"
        )
        return SkillResolution(
            intent: .code(name: "Generate patch", command: command, workspaceRelativePath: path, text: taskContext.goal.description),
            repositorySnapshotID: snapshot.id
        )
    }
}
