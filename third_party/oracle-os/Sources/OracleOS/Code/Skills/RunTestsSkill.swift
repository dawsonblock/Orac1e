import Foundation

public final class RunTestsSkill: CodeSkill {
    public let name = "run_tests"

    public init() {}

    public func resolve(
        taskContext: TaskContext,
        state: WorldState,
memoryStore _: UnifiedMemoryStore
    ) throws -> SkillResolution {
        let workspaceRoot = try CodeSkillSupport.workspaceRoot(taskContext: taskContext, state: state)
        let snapshot = try CodeSkillSupport.repositorySnapshot(state: state, workspaceRoot: workspaceRoot)
        guard let command = BuildToolDetector.defaultTestCommand(for: snapshot.buildTool, workspaceRoot: workspaceRoot) else {
            throw CodeSkillResolutionError.noRelevantFiles("No test command available")
        }
        return SkillResolution(
            intent: .code(name: "Run tests", command: command),
            repositorySnapshotID: snapshot.id
        )
    }
}
