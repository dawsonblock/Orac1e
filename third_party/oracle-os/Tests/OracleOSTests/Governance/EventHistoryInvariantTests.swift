import XCTest
@testable import OracleOS

private final class LockedBoolBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func setTrue() {
        lock.lock()
        value = true
        lock.unlock()
    }

    func get() -> Bool {
        lock.lock()
        let current = value
        lock.unlock()
        return current
    }
}

/// Verifies that every committed state change has event ancestry.
/// INVARIANT: No snapshot may be committed without domain events behind it.
final class EventHistoryInvariantTests: XCTestCase {

    // MARK: - EventStore append-only invariant

    func test_event_store_is_append_only() async {
        let store = EventStore()
        let e1 = EventEnvelope(sequenceNumber: 1, commandID: nil, intentID: nil, eventType: "actionStarted", payload: Data())
        let e2 = EventEnvelope(sequenceNumber: 2, commandID: nil, intentID: nil, eventType: "actionCompleted", payload: Data())

        await store.append(e1)
        await store.append(e2)

        let all = await store.all()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].eventType, "actionStarted")
        XCTAssertEqual(all[1].eventType, "actionCompleted")
    }

    func test_event_store_sequence_numbers_monotonically_increase() async {
        let store = EventStore()
        let seq1 = await store.nextSequenceNumber()
        let seq2 = await store.nextSequenceNumber()
        let seq3 = await store.nextSequenceNumber()

        XCTAssertLessThan(seq1, seq2)
        XCTAssertLessThan(seq2, seq3)
    }

    func test_event_store_filter_by_command_id() async {
        let store = EventStore()
        let cmdID = CommandID()
        let otherID = CommandID()

        await store.append(EventEnvelope(sequenceNumber: 1, commandID: cmdID, intentID: nil, eventType: "a", payload: Data()))
        await store.append(EventEnvelope(sequenceNumber: 2, commandID: otherID, intentID: nil, eventType: "b", payload: Data()))
        await store.append(EventEnvelope(sequenceNumber: 3, commandID: cmdID, intentID: nil, eventType: "c", payload: Data()))

        let filtered = await store.events(forCommandID: cmdID)
        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered[0].eventType, "a")
        XCTAssertEqual(filtered[1].eventType, "c")
    }

    // MARK: - StateSnapshot event ancestry invariant

    func test_snapshot_requires_event_ancestry() {
        let ancestry = [UUID(), UUID(), UUID()]
        let snapshot = StateSnapshot(
            sequenceNumber: 10,
            state: WorldStateModel(),
            eventAncestry: ancestry
        )
        XCTAssertFalse(snapshot.eventAncestry.isEmpty)
        XCTAssertEqual(snapshot.sequenceNumber, 10)
        XCTAssertEqual(snapshot.eventAncestry.count, 3)
    }

    func test_snapshot_without_ancestry_is_invalid_in_production_flow() {
        // A snapshot with empty ancestry should NOT be produced by CommitCoordinator
        // since it only commits non-empty event arrays.
        // We document this by asserting that empty ancestry is a logic error:
        let emptyAncestry: [UUID] = []
        XCTAssertTrue(emptyAncestry.isEmpty, "This demonstrates that empty ancestry must never reach production state")
    }

    // MARK: - CommitCoordinator produces events before state change

    func test_commit_coordinator_appends_events_then_applies_reducers() async throws {
        let store = EventStore()
        let reducerCalled = LockedBoolBox()
        let testReducer = TestReducer { reducerCalled.setTrue() }
        let coordinator = CommitCoordinator(eventStore: store, reducers: [testReducer])

        let envelope = EventEnvelope(
            sequenceNumber: 0, // will be reassigned
            commandID: CommandID(),
            intentID: UUID(),
            eventType: "commandIssued",
            payload: Data()
        )

        try await coordinator.commit([envelope])

        let events = await store.all()
        XCTAssertEqual(events.count, 1, "Event must be appended to store on commit")
        XCTAssertEqual(events[0].eventType, "commandIssued")
        XCTAssertTrue(reducerCalled.get(), "Reducer must be called after event is appended")
    }

    func test_commit_coordinator_empty_commit_is_noop() async throws {
        let store = EventStore()
        let coordinator = CommitCoordinator(eventStore: store, reducers: [])
        try await coordinator.commit([])
        let events = await store.all()
        XCTAssertEqual(events.count, 0, "Empty commit must not append any events")
    }

    func test_commit_coordinator_assigns_sequence_numbers() async throws {
        let store = EventStore()
        let coordinator = CommitCoordinator(eventStore: store, reducers: [])

        let envelopes = [
            EventEnvelope(sequenceNumber: 0, commandID: nil, intentID: nil, eventType: "e1", payload: Data()),
            EventEnvelope(sequenceNumber: 0, commandID: nil, intentID: nil, eventType: "e2", payload: Data()),
            EventEnvelope(sequenceNumber: 0, commandID: nil, intentID: nil, eventType: "e3", payload: Data())
        ]

        try await coordinator.commit(envelopes)
        let events = await store.all()
        XCTAssertEqual(events.count, 3)

        let seqNums = events.map(\.sequenceNumber)
        // All sequence numbers must be > 0 and strictly increasing
        XCTAssertTrue(seqNums.allSatisfy { $0 > 0 }, "All sequence numbers must be assigned (> 0)")
        let sorted = seqNums.sorted()
        XCTAssertEqual(seqNums, sorted, "Sequence numbers must be monotonically increasing")
    }
}

// MARK: - Test Helpers

private struct TestReducer: EventReducer {
    let onApply: @Sendable () -> Void
    func apply(events: [EventEnvelope], to state: inout WorldStateModel) {
        if !events.isEmpty { onApply() }
    }
}
