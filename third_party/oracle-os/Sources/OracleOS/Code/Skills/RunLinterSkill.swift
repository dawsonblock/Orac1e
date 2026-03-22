import Foundation

public final class RunLinterSkill: CodeSkill {
    public let name = "run_linter"

    public init() {}

    public func resolve(
        taskContext: TaskContext,
        state: WorldState,
memoryStore _: UnifiedMemoryStore
    ) throws -> SkillResolution {
        let workspaceRoot = try CodeSkillSupport.workspaceRoot(taskContext: taskContext, state: state)
        let snapshot = try CodeSkillSupport.repositorySnapshot(state: state, workspaceRoot: workspaceRoot)
        let arguments: [String]
        let summary: String
        if snapshot.buildTool == .swiftPackage {
            arguments = ["swift", "build", "-Xswiftc", "-warnings-as-errors"]
            summary = "swift lint-style build"
        } else {
            arguments = []
            summary = "lint project"
        }
        let command = CodeSkillSupport.command(
            category: .linter,
            workspaceRoot: workspaceRoot,
            summary: summary,
            arguments: arguments
        )
        return SkillResolution(intent: .code(name: "Run linter", command: command), repositorySnapshotID: snapshot.id)
    }
}
