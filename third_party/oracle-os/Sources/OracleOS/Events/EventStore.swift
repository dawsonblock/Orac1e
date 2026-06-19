import Foundation

/// Append-only event log. The single source of truth for all state changes.
/// INVARIANT: Events are never deleted or mutated after append.
public actor EventStore {
    private var envelopes: [EventEnvelope] = []
    private var sequenceCounter: Int = 0

    public init() {}

    public func append(_ envelope: EventEnvelope) {
        envelopes.append(envelope)
    }

    public func append(contentsOf newEnvelopes: [EventEnvelope]) {
        envelopes.append(contentsOf: newEnvelopes)
    }

    public func all() -> [EventEnvelope] { envelopes }

    public func events(forCommandID id: CommandID) -> [EventEnvelope] {
        envelopes.filter { $0.commandID == id }
    }

    public func events(after sequenceNumber: Int) -> [EventEnvelope] {
        envelopes.filter { $0.sequenceNumber > sequenceNumber }
    }

    /// Returns the next sequence number to use.
    /// Increments first to ensure each call returns a unique, monotonically increasing value.
    public func nextSequenceNumber() -> Int {
        sequenceCounter += 1
        return sequenceCounter
    }
}
