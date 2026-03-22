import Foundation

public final class RunFormatterSkill: CodeSkill {
    public let name = "run_formatter"

    public init() {}

    public func resolve(
        taskContext: TaskContext,
        state: WorldState,
memoryStore _: UnifiedMemoryStore
    ) throws -> SkillResolution {
        let workspaceRoot = try CodeSkillSupport.workspaceRoot(taskContext: taskContext, state: state)
        let snapshot = try CodeSkillSupport.repositorySnapshot(state: state, workspaceRoot: workspaceRoot)
        let command = CodeSkillSupport.command(
            category: .formatter,
            workspaceRoot: workspaceRoot,
            summary: snapshot.buildTool == .swiftPackage ? "swift format" : "format project",
            arguments: snapshot.buildTool == .swiftPackage ? ["swift", "format", "."] : []
        )
        return SkillResolution(intent: .code(name: "Run formatter", command: command), repositorySnapshotID: snapshot.id)
    }
}
