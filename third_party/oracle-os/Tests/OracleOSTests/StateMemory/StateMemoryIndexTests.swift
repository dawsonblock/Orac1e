import Foundation
import Testing
@testable import OracleOS

@Suite("State Memory Index")
struct StateMemoryIndexTests {

    // MARK: - Lookup

    @Test("Empty index returns nil for any state")
    func emptyIndexReturnsNil() {
        let index = StateMemoryIndex()
        let state = CompressedUIState(app: "Finder", elements: [])
        #expect(index.lookup(state) == nil)
        #expect(index.bestAction(for: state) == nil)
    }

    @Test("Recording an action makes it retrievable")
    func recordMakesRetrievable() {
        let index = StateMemoryIndex()
        let state = CompressedUIState(
            app: "Slack",
            elements: [
                SemanticElement(id: "btn-1", kind: .button, label: "Send"),
            ]
        )
        index.record(state: state, actionName: "click_Send", success: true)
        let entry = index.lookup(state)
        #expect(entry != nil)
        #expect(entry?.actionStats["click_Send"]?.attempts == 1)
        #expect(entry?.actionStats["click_Send"]?.successes == 1)
    }

    @Test("bestAction returns highest success rate action")
    func bestActionReturnsHighestRate() {
        let index = StateMemoryIndex()
        let state = CompressedUIState(
            app: "Mail",
            elements: [
                SemanticElement(id: "btn-send", kind: .button, label: "Send"),
                SemanticElement(id: "btn-save", kind: .button, label: "Save"),
            ]
        )
        // Record send with 100% success
        index.record(state: state, actionName: "click_Send", success: true)
        index.record(state: state, actionName: "click_Send", success: true)
        // Record save with 50% success
        index.record(state: state, actionName: "click_Save", success: true)
        index.record(state: state, actionName: "click_Save", success: false)

        #expect(index.bestAction(for: state) == "click_Send")
    }

    // MARK: - State signature

    @Test("Same elements produce same signature")
    func sameElementsSameSignature() {
        let state1 = CompressedUIState(
            app: "Finder",
            elements: [
                SemanticElement(id: "a", kind: .button, label: "Open"),
                SemanticElement(id: "b", kind: .input, label: "Search"),
            ]
        )
        let state2 = CompressedUIState(
            app: "Finder",
            elements: [
                SemanticElement(id: "a", kind: .button, label: "Open"),
                SemanticElement(id: "b", kind: .input, label: "Search"),
            ]
        )
        let sig1 = StateSignature(from: state1)
        let sig2 = StateSignature(from: state2)
        #expect(sig1 == sig2)
    }

    @Test("Different elements produce different signatures")
    func differentElementsDifferentSignature() {
        let state1 = CompressedUIState(
            app: "Finder",
            elements: [
                SemanticElement(id: "a", kind: .button, label: "Open"),
            ]
        )
        let state2 = CompressedUIState(
            app: "Finder",
            elements: [
                SemanticElement(id: "a", kind: .button, label: "Close"),
            ]
        )
        let sig1 = StateSignature(from: state1)
        let sig2 = StateSignature(from: state2)
        #expect(sig1 != sig2)
    }

    // MARK: - Eviction

    @Test("Index evicts oldest entries when capacity exceeded")
    func evictsOldestEntries() {
        let index = StateMemoryIndex(maxEntries: 2)
        let state1 = CompressedUIState(app: "App1", elements: [])
        let state2 = CompressedUIState(app: "App2", elements: [])
        let state3 = CompressedUIState(app: "App3", elements: [])

        index.record(state: state1, actionName: "a", success: true)
        index.record(state: state2, actionName: "b", success: true)
        #expect(index.count == 2)

        index.record(state: state3, actionName: "c", success: true)
        #expect(index.count == 2)
        // state1 was the oldest and should have been evicted
        #expect(index.lookup(state1) == nil)
        #expect(index.lookup(state3) != nil)
    }

    // MARK: - ActionStats

    @Test("ActionStats computes correct success rate")
    func actionStatsSuccessRate() {
        var stats = ActionStats(actionName: "test", attempts: 4, successes: 3)
        #expect(stats.successRate == 0.75)
        stats.attempts += 1
        #expect(stats.successRate == 0.6)
    }

    @Test("ActionStats with zero attempts returns zero rate")
    func actionStatsZeroAttempts() {
        let stats = ActionStats()
        #expect(stats.successRate == 0)
    }

    // MARK: - likelyActions

    @Test("likelyActions returns empty for unknown state")
    func likelyActionsEmptyForUnknown() {
        let index = StateMemoryIndex()
        let state = CompressedUIState(app: "Unknown", elements: [])
        #expect(index.likelyActions(for: state).isEmpty)
    }

    @Test("likelyActions returns actions sorted by success rate")
    func likelyActionsSortedByRate() {
        let index = StateMemoryIndex()
        let state = CompressedUIState(
            app: "Mail",
            elements: [
                SemanticElement(id: "btn-send", kind: .button, label: "Send"),
            ]
        )
        // click_Send: 2/2 = 100%
        index.record(state: state, actionName: "click_Send", success: true)
        index.record(state: state, actionName: "click_Send", success: true)
        // click_Save: 1/3 ≈ 33%
        index.record(state: state, actionName: "click_Save", success: true)
        index.record(state: state, actionName: "click_Save", success: false)
        index.record(state: state, actionName: "click_Save", success: false)
        // click_Draft: 1/2 = 50%
        index.record(state: state, actionName: "click_Draft", success: true)
        index.record(state: state, actionName: "click_Draft", success: false)

        let likely = index.likelyActions(for: state)
        #expect(likely.count == 3)
        #expect(likely[0].actionName == "click_Send")
        #expect(likely[0].successRate == 1.0)
        #expect(likely[1].actionName == "click_Draft")
        #expect(likely[1].successRate == 0.5)
        #expect(likely[2].actionName == "click_Save")
    }

    @Test("likelyActions includes actionName in stats")
    func likelyActionsIncludesActionName() {
        let index = StateMemoryIndex()
        let state = CompressedUIState(app: "App", elements: [])
        index.record(state: state, actionName: "my_action", success: true)

        let likely = index.likelyActions(for: state)
        #expect(likely.count == 1)
        #expect(likely[0].actionName == "my_action")
    }
}
