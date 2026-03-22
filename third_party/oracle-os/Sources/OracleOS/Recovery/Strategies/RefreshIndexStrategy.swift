import Foundation

public struct RefreshIndexStrategy: RecoveryStrategy {
    public let name = "refresh_index"
    public let layer: RecoveryLayer = .modeSwitch

    public init() {}

    public func prepare(
        failure _: FailureClass,
        state: WorldState,
memoryStore _: UnifiedMemoryStore
    ) async throws -> RecoveryPreparation? {
        guard let repositorySnapshot = state.repositorySnapshot else {
            return nil
        }

        let command = CommandSpec(
            category: .indexRepository,
            executable: "/usr/bin/env",
            arguments: [],
            workspaceRoot: repositorySnapshot.workspaceRoot,
            summary: "index repository"
        )

        return RecoveryPreparation(
            strategyName: name,
            resolution: SkillResolution(
                intent: .code(name: "Refresh repository index", command: command),
                repositorySnapshotID: repositorySnapshot.id
            ),
            notes: ["refreshing repository index"]
        )
    }
}
