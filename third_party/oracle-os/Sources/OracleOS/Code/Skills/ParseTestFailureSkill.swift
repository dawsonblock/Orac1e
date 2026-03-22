import Foundation

public final class ParseTestFailureSkill: CodeSkill {
    public let name = "parse_test_failure"

    public init() {}

    public func resolve(
        taskContext: TaskContext,
        state: WorldState,
memoryStore _: UnifiedMemoryStore
    ) throws -> SkillResolution {
        let workspaceRoot = try CodeSkillSupport.workspaceRoot(taskContext: taskContext, state: state)
        let snapshot = try CodeSkillSupport.repositorySnapshot(state: state, workspaceRoot: workspaceRoot)
        let command = CodeSkillSupport.command(
            category: .parseTestFailure,
            workspaceRoot: workspaceRoot,
            summary: "parse test failures"
        )
        return SkillResolution(
            intent: .code(name: "Parse test failure", command: command, text: taskContext.goal.description),
            repositorySnapshotID: snapshot.id
        )
    }
}
