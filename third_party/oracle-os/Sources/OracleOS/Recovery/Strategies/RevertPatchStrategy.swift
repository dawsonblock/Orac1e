import Foundation

public struct RevertPatchStrategy: RecoveryStrategy {
    public let name = "revert_patch"
    public let layer: RecoveryLayer = .skillFallback

    public init() {}

    public func prepare(
        failure _: FailureClass,
        state: WorldState,
        memoryStore _: UnifiedMemoryStore
    ) async throws -> RecoveryPreparation? {
        guard state.lastAction?.agentKind == .code else {
            return nil
        }

        return nil
    }
}
