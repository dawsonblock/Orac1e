public struct RetryStrategy: RecoveryStrategy {

    public let name = "retry"
    public let layer: RecoveryLayer = .localRetry

    public func prepare(
        failure: FailureClass,
        state: WorldState,
        memoryStore _: UnifiedMemoryStore
    ) async throws -> RecoveryPreparation? {
        guard let last = state.lastAction else {
            return nil
        }

        return RecoveryPreparation(
            strategyName: name,
            resolution: SkillResolution(intent: last),
            notes: ["retrying previous \(last.action) action after \(failure.rawValue)"]
        )
    }
}
