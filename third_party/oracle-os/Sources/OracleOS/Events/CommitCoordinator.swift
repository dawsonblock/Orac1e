import Foundation

/// Orchestrates the commit flow: appends events → runs reducers → emits new snapshot.
/// INVARIANT: No state write may bypass CommitCoordinator.
public actor CommitCoordinator {
    private let eventStore: EventStore
    private let reducers: [any EventReducer]
    private(set) var currentState: WorldStateModel

    public init(eventStore: EventStore, reducers: [any EventReducer], initialState: WorldStateModel = WorldStateModel()) {
        self.eventStore = eventStore
        self.reducers = reducers
        self.currentState = initialState
    }

    public func commit(_ envelopes: [EventEnvelope]) async throws {
        guard !envelopes.isEmpty else { return }

        // Assign sequence numbers to envelopes before appending
        var numberedEnvelopes = envelopes
        for i in 0..<numberedEnvelopes.count {
            let seq = await eventStore.nextSequenceNumber()
            // Create new envelope with sequence number (struct is immutable)
            let old = numberedEnvelopes[i]
            numberedEnvelopes[i] = EventEnvelope(
                id: old.id,
                sequenceNumber: seq,
                commandID: old.commandID,
                intentID: old.intentID,
                timestamp: old.timestamp,
                eventType: old.eventType,
                payload: old.payload
            )
        }

        await eventStore.append(contentsOf: numberedEnvelopes)
        for reducer in reducers {
            reducer.apply(events: numberedEnvelopes, to: &currentState)
        }
    }

    /// Returns a copy of the current state to prevent direct mutation.
    /// Returns WorldModelSnapshot (value type) from the model's snapshot property.
    public func snapshot() -> WorldModelSnapshot {
        // WorldStateModel.snapshot returns WorldModelSnapshot (a struct/value type)
        // This is the safe way to expose state without giving mutable access
        return currentState.snapshot
    }
}
