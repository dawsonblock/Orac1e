import Foundation

public struct RerunFocusedTestsStrategy: RecoveryStrategy {
    public let name = "rerun_focused_tests"
    public let layer: RecoveryLayer = .localRetry

    public init() {}

    public func prepare(
        failure _: FailureClass,
        state: WorldState,
        memoryStore _: UnifiedMemoryStore
    ) async throws -> RecoveryPreparation? {
        guard let snapshot = state.repositorySnapshot,
              !snapshot.testGraph.tests.isEmpty
        else {
            return nil
        }

        let workspaceRoot = URL(fileURLWithPath: snapshot.workspaceRoot, isDirectory: true)
        guard let command = BuildToolDetector.defaultTestCommand(for: snapshot.buildTool, workspaceRoot: workspaceRoot) else {
            return nil
        }

        return RecoveryPreparation(
            strategyName: name,
            resolution: SkillResolution(
                intent: .code(name: "Rerun focused tests", command: command),
                repositorySnapshotID: snapshot.id
            ),
            notes: ["rerunning focused tests"]
        )
    }
}
