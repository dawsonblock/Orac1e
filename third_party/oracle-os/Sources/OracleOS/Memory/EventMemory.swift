import Foundation
/// Memory derived from event history — read-only.
public actor EventMemory {
    private let eventStore: EventStore
    public init(eventStore: EventStore) { self.eventStore = eventStore }
    public func query(pattern: String) async -> [MemoryCandidate] {
        let events = await eventStore.all()
        return events.map { MemoryCandidate(id: $0.id, content: $0.eventType, confidence: 0.5, source: "event") }
    }
}
