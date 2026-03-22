import XCTest
@testable import OracleOS

/// Verifies that a runtime cycle can be replayed from event history
/// and produce the same committed state snapshot.
final class EventReplayTests: XCTestCase {

    func test_event_replay_produces_deterministic_state() async throws {
        let store1 = EventStore()
        let coordinator1 = CommitCoordinator(
            eventStore: store1,
            reducers: DefaultReducers.make()
        )

        let commandID = CommandID()
        let intentID = UUID()
        let repoPayload = try JSONEncoder().encode(RepositoryObservedPayload(
            repositoryRoot: "/tmp/repo",
            activeBranch: "main",
            isGitDirty: true,
            openFileCount: 3
        ))
        let buildPayload = try JSONEncoder().encode(BuildCompletedPayload(succeeded: false))

        let envelopes = [
            EventEnvelope(sequenceNumber: 1, commandID: commandID, intentID: intentID,
                          eventType: EventKinds.repositoryObserved, payload: repoPayload),
            EventEnvelope(sequenceNumber: 2, commandID: commandID, intentID: intentID,
                          eventType: EventKinds.buildCompleted, payload: buildPayload),
            EventEnvelope(sequenceNumber: 3, commandID: commandID, intentID: intentID,
                          eventType: EventKinds.commandSucceeded, payload: Data())
        ]

        try await coordinator1.commit(envelopes)
        let snapshot1 = await coordinator1.snapshot()

        let allEvents = await store1.all()
        let store2 = EventStore()
        let coordinator2 = CommitCoordinator(
            eventStore: store2,
            reducers: DefaultReducers.make()
        )
        try await coordinator2.commit(allEvents)
        let snapshot2 = await coordinator2.snapshot()

        XCTAssertEqual(allEvents.count, 3)
        XCTAssertEqual(snapshot1.repositoryRoot, snapshot2.repositoryRoot)
        XCTAssertEqual(snapshot1.activeBranch, snapshot2.activeBranch)
        XCTAssertEqual(snapshot1.isGitDirty, snapshot2.isGitDirty)
        XCTAssertEqual(snapshot1.buildSucceeded, snapshot2.buildSucceeded)
        XCTAssertEqual(snapshot1.cycleCount, snapshot2.cycleCount)
        XCTAssertEqual(snapshot1.lastSequenceNumber, snapshot2.lastSequenceNumber)
    }

    func test_event_replay_builds_timeline() async throws {
        let store = EventStore()
        let commandID = CommandID()
        let cycleID = UUID()

        await store.append(EventEnvelope(
            sequenceNumber: 1,
            commandID: commandID,
            intentID: cycleID,
            eventType: EventKinds.commandStarted,
            payload: Data()
        ))
        await store.append(EventEnvelope(
            sequenceNumber: 2,
            commandID: commandID,
            intentID: cycleID,
            eventType: EventKinds.commandSucceeded,
            payload: Data()
        ))

        let replay = EventReplay(eventStore: store)
        let timeline = try await replay.replay(cycleID: cycleID)

        XCTAssertEqual(timeline.events.count, 2)
        XCTAssertFalse(timeline.events.isEmpty)
    }

    func test_timeline_builder_preserves_event_order() {
        let events = [
            EventEnvelope(sequenceNumber: 1, commandID: nil, intentID: nil, eventType: "first", payload: Data()),
            EventEnvelope(sequenceNumber: 2, commandID: nil, intentID: nil, eventType: "second", payload: Data()),
            EventEnvelope(sequenceNumber: 3, commandID: nil, intentID: nil, eventType: "third", payload: Data())
        ]

        let timeline = TimelineBuilder().build(from: events)
        XCTAssertEqual(timeline.events.count, 3)
        XCTAssertEqual(timeline.events[0].eventType, "first")
        XCTAssertEqual(timeline.events[2].eventType, "third")
    }

    func test_snapshot_reflects_committed_events_with_default_reducers() async throws {
        let store = EventStore()
        let coordinator = CommitCoordinator(eventStore: store, reducers: DefaultReducers.make())

        let initial = await coordinator.snapshot()
        XCTAssertEqual(initial.cycleCount, 0)

        let payload = try JSONEncoder().encode(AppFocusedPayload(appName: "com.apple.Safari"))
        try await coordinator.commit([
            EventEnvelope(sequenceNumber: 1, commandID: nil, intentID: nil, eventType: EventKinds.appFocused, payload: payload),
            EventEnvelope(sequenceNumber: 2, commandID: nil, intentID: nil, eventType: EventKinds.commandSucceeded, payload: Data())
        ])

        let snapshot = await coordinator.snapshot()
        let eventsInStore = await store.all()
        XCTAssertEqual(eventsInStore.count, 2)
        XCTAssertEqual(snapshot.activeApplication, "com.apple.Safari")
        XCTAssertEqual(snapshot.cycleCount, 1)
        XCTAssertEqual(snapshot.lastSequenceNumber, 2)
    }
}
