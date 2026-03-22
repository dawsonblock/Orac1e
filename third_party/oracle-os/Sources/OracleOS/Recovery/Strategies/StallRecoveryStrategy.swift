/// StallRecoveryStrategy.swift
///
/// Replan-layer recovery triggered when the execution loop detects a stall:
/// the same action was attempted in the same world state multiple times
/// without producing any observable change.
///
/// Strategy:
///   1. Force a focus reset on the frontmost application so the observation
///      layer rebuilds its snapshot from scratch.
///   2. Tag the resolution with a "diversify" note that the planner reads to
///      avoid re-selecting the same skill on the next cycle.
@MainActor
public struct StallRecoveryStrategy: RecoveryStrategy {

    public let name = "stall_recovery"
    public let layer: RecoveryLayer = .replan

    public func prepare(
        failure: FailureClass,
        state: WorldState,
        memoryStore _: UnifiedMemoryStore
    ) async throws -> RecoveryPreparation? {
        // If we have a known frontmost app, force-refocus it so the AX tree
        // is rebuilt fresh. Otherwise fall back to a noop scroll that still
        // forces an observation refresh.
        let app = state.observation.app ?? "Finder"

        let refocusIntent = ActionIntent.focus(app: app)

        return RecoveryPreparation(
            strategyName: name,
            resolution: SkillResolution(intent: refocusIntent),
            notes: [
                "stall recovery: resetting observation by refocusing \(app)",
                "diversify: do not repeat the last [\(state.lastAction?.action ?? "unknown")] action",
            ]
        )
    }
}
