import Foundation

public struct DismissModalStrategy: RecoveryStrategy {
    public let name = "dismiss_modal"
    public let layer: RecoveryLayer = .interruptionHandling

    public init() {}

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
            resolution: SkillResolution(intent: .press(app: app, key: "escape")),
            notes: ["dismissing modal after \(failure.rawValue)"]
        )
    }
}
