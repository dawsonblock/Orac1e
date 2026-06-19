import Foundation

public final class ParseBuildFailureSkill: CodeSkill {
    public let name = "parse_build_failure"

    public init() {}

    public func resolve(
        taskContext: TaskContext,
        state: WorldState,
memoryStore _: UnifiedMemoryStore
    ) throws -> SkillResolution {
        let workspaceRoot = try CodeSkillSupport.workspaceRoot(taskContext: taskContext, state: state)
        let snapshot = try CodeSkillSupport.repositorySnapshot(state: state, workspaceRoot: workspaceRoot)
        let command = CodeSkillSupport.command(
            category: .parseBuildFailure,
            workspaceRoot: workspaceRoot,
            summary: "parse build failures"
        )
        return SkillResolution(
            intent: .code(name: "Parse build failure", command: command, text: taskContext.goal.description),
            repositorySnapshotID: snapshot.id
        )
    }
}
