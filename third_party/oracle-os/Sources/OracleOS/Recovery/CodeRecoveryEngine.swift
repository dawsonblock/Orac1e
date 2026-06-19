import Foundation

@MainActor
public final class CodeRecoveryEngine {
    private let engine: RecoveryEngine

    public init(engine: RecoveryEngine = RecoveryEngine()) {
        self.engine = engine
    }

    public func recover(
        failure: FailureClass,
        state: WorldState,
memoryStore: UnifiedMemoryStore? = nil
    ) async -> RecoveryAttempt {
        await engine.recover(failure: failure, state: state, memoryStore: memoryStore)
    }
}
