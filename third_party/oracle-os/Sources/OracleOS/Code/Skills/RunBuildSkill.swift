import Foundation

public final class RunBuildSkill: CodeSkill {
    public let name = "run_build"

    public init() {}

    public func resolve(
        taskContext: TaskContext,
        state: WorldState,
memoryStore _: UnifiedMemoryStore
    ) throws -> SkillResolution {
        let workspaceRoot = try CodeSkillSupport.workspaceRoot(taskContext: taskContext, state: state)
        let snapshot = try CodeSkillSupport.repositorySnapshot(state: state, workspaceRoot: workspaceRoot)
        guard let command = BuildToolDetector.defaultBuildCommand(for: snapshot.buildTool, workspaceRoot: workspaceRoot) else {
            throw CodeSkillResolutionError.noRelevantFiles("No build command available")
        }
        return SkillResolution(
            intent: .code(name: "Run build", command: command),
            repositorySnapshotID: snapshot.id
        )
    }
}
