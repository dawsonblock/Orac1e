public struct RefocusAppStrategy: RecoveryStrategy {

    public let name = "refocus_app"
    public let layer: RecoveryLayer = .alternateTargeting

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
            notes: ["refocusing \(app) after \(failure.rawValue)"]
        )
    }
}
