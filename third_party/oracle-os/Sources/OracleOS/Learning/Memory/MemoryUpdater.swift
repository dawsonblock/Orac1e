import Foundation

public struct MemoryUpdater {

    public static func recordSuccess(
        element: UnifiedElement,
        state: WorldState,
store: UnifiedMemoryStore
    ) {
        let key = "\(state.observation.app ?? "unknown")-\(element.label ?? "unknown")"

        let control =
            KnownControl(
                key: key,
                app: state.observation.app ?? "unknown",
                label: element.label,
                role: element.role,
                elementID: element.id,
                successCount: 1,
                lastUsed: Date()
            )
        store.recordControl(control)
    }

    public static func recordFailure(
        failure: FailureClass,
        state: WorldState,
store: UnifiedMemoryStore
    ) {
        let pattern =
            FailurePattern(
                app: state.observation.app ?? "unknown",
                failure: failure,
                action: state.lastAction?.name ?? "unknown"
            )

        store.recordFailure(pattern)
    }
}
