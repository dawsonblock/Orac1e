public struct RefreshObservationStrategy: RecoveryStrategy {

    public let name = "refresh_observation"
    public let layer: RecoveryLayer = .localRetry

    public func prepare(
        failure: FailureClass,
        state: WorldState,
memoryStore _: UnifiedMemoryStore
    ) async throws -> RecoveryPreparation? {
        guard let app = state.observation.app, !app.isEmpty else {
            return nil
        }

        return RecoveryPreparation(
            strategyName: name,
            resolution: SkillResolution(intent: .focus(app: app)),
            notes: ["refreshing observation by refocusing \(app) after \(failure.rawValue)"]
        )
    }
}
