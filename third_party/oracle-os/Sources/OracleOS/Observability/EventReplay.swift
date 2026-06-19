import Foundation

/// Replays a runtime cycle from event history into a readable timeline.
/// Traces derive from event history and execution outcomes — not scattered manual logs.
public struct EventReplay {
    private let eventStore: EventStore

    public init(eventStore: EventStore) {
        self.eventStore = eventStore
    }

    /// Replay all events for a given cycle (identified by intentID) into a timeline.
    public func replay(cycleID: UUID) async throws -> Timeline {
        let allEvents = await eventStore.all()
        let cycleEvents = allEvents.filter { $0.intentID == cycleID }
        return TimelineBuilder().build(from: cycleEvents)
    }

    /// Replay all events (no filtering) — useful for full run analysis.
    public func replayAll() async -> Timeline {
        let events = await eventStore.all()
        return TimelineBuilder().build(from: events)
    }

    /// Replay events after a given sequence number — for incremental replay.
    public func replay(after sequenceNumber: Int) async -> Timeline {
        let events = await eventStore.events(after: sequenceNumber)
        return TimelineBuilder().build(from: events)
    }
}
