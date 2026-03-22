import Foundation
import Testing
@testable import OracleOS

@Suite("Diagnostics — MetricsRecorder")
struct MetricsRecorderTests {

    @Test("New recorder starts with zero metrics")
    func newRecorderStartsAtZero() {
        let recorder = MetricsRecorder()
        let m = recorder.current
        #expect(m.actionsAttempted == 0)
        #expect(m.actionsSucceeded == 0)
        #expect(m.patchAttempts == 0)
        #expect(m.searchCycles == 0)
        #expect(m.actionSuccessRate == 0)
    }

    @Test("recordAction increments counters correctly")
    func recordActionIncrements() {
        let recorder = MetricsRecorder()
        recorder.recordAction(success: true, elapsedMs: 100)
        recorder.recordAction(success: false, wrongTarget: true, elapsedMs: 200)
        recorder.recordAction(success: true, elapsedMs: 150, isPatch: true)

        let m = recorder.current
        #expect(m.actionsAttempted == 3)
        #expect(m.actionsSucceeded == 2)
        #expect(m.wrongTargetCount == 1)
        #expect(m.patchAttempts == 1)
        #expect(m.patchSuccesses == 1)
        #expect(m.totalElapsedMs == 450)
    }

    @Test("recordSearchCycle tracks candidate distribution")
    func recordSearchCycleTracks() {
        let recorder = MetricsRecorder()
        recorder.recordSearchCycle(
            candidatesGenerated: 5,
            memoryCandidates: 2,
            graphCandidates: 2,
            llmFallbackCandidates: 1
        )
        recorder.recordSearchCycle(
            candidatesGenerated: 3,
            memoryCandidates: 1,
            graphCandidates: 2
        )

        let m = recorder.current
        #expect(m.searchCycles == 2)
        #expect(m.candidatesGenerated == 8)
        #expect(m.memoryCandidates == 3)
        #expect(m.graphCandidates == 4)
        #expect(m.llmFallbackCandidates == 1)
    }

    @Test("Computed rates are correct")
    func computedRatesAreCorrect() {
        let recorder = MetricsRecorder()
        recorder.recordAction(success: true, elapsedMs: 100)
        recorder.recordAction(success: true, elapsedMs: 200)
        recorder.recordAction(success: false, elapsedMs: 300)

        let m = recorder.current
        #expect(m.actionSuccessRate > 0.66)
        #expect(m.actionSuccessRate < 0.67)
        #expect(m.meanTimePerAction == 200)
    }

    @Test("Wrong-target rate computes correctly")
    func wrongTargetRate() {
        let recorder = MetricsRecorder()
        recorder.recordAction(success: false, wrongTarget: true, elapsedMs: 50)
        recorder.recordAction(success: true, elapsedMs: 50)

        let m = recorder.current
        #expect(m.wrongTargetRate == 0.5)
    }

    @Test("Patch success rate computes correctly")
    func patchSuccessRate() {
        let recorder = MetricsRecorder()
        recorder.recordAction(success: true, isPatch: true)
        recorder.recordAction(success: false, isPatch: true)
        recorder.recordAction(success: true, isPatch: true)

        let m = recorder.current
        #expect(m.patchAttempts == 3)
        #expect(m.patchSuccesses == 2)
        #expect(m.patchSuccessRate > 0.66)
        #expect(m.patchSuccessRate < 0.67)
    }

    @Test("Reset clears all metrics")
    func resetClearsAll() {
        let recorder = MetricsRecorder()
        recorder.recordAction(success: true, elapsedMs: 100)
        recorder.recordSearchCycle(candidatesGenerated: 5)
        recorder.reset()

        let m = recorder.current
        #expect(m.actionsAttempted == 0)
        #expect(m.searchCycles == 0)
    }

    @Test("Persist and load round-trips metrics")
    func persistAndLoadRoundTrips() throws {
        let path = "/tmp/oracle_test_metrics_\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let recorder = MetricsRecorder(outputPath: path)
        recorder.recordAction(success: true, elapsedMs: 42)
        recorder.recordSearchCycle(candidatesGenerated: 3, memoryCandidates: 2)
        try recorder.persist()

        let loaded = MetricsRecorder(outputPath: path)
        try loaded.load()
        let m = loaded.current
        #expect(m.actionsAttempted == 1)
        #expect(m.actionsSucceeded == 1)
        #expect(m.totalElapsedMs == 42)
        #expect(m.searchCycles == 1)
        #expect(m.memoryCandidates == 2)
    }

    @Test("Recovery and retry counters work")
    func recoveryAndRetryCounters() {
        let recorder = MetricsRecorder()
        recorder.recordAction(success: false, isRetry: true, isRecovery: true)
        recorder.recordAction(success: true, isRetry: true)

        let m = recorder.current
        #expect(m.retries == 2)
        #expect(m.recoveryCount == 1)
    }
}
