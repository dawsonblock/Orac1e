import Foundation
import Testing
@testable import OracleOS

@Suite("Trace Replay Engine")
struct TraceReplayEngineTests {

    let engine = TraceReplayEngine()

    // MARK: - buildStep

    @Test("buildStep produces a ReplayStep from a CriticVerdict")
    func buildStepFromVerdict() {
        let verdict = CriticVerdict(
            outcome: .success,
            preStateHash: "hash-a",
            postStateHash: "hash-b",
            actionName: "click_Send",
            stateChanged: true,
            notes: ["state changed"]
        )
        let step = engine.buildStep(
            verdict: verdict,
            schemaKind: .click,
            elapsedMs: 42
        )
        #expect(step.preStateHash == "hash-a")
        #expect(step.postStateHash == "hash-b")
        #expect(step.actionName == "click_Send")
        #expect(step.schemaKind == .click)
        #expect(step.criticOutcome == .success)
        #expect(step.elapsedMs == 42)
    }

    // MARK: - compare

    @Test("Identical traces produce no divergences")
    func identicalTracesNoDivergences() {
        let step = ReplayStep(
            preStateHash: "h1",
            postStateHash: "h2",
            actionName: "click",
            criticOutcome: .success
        )
        let trace = ReplayTrace(steps: [step, step])
        let divergences = engine.compare(expected: trace, actual: trace)
        #expect(divergences.isEmpty)
    }

    @Test("Different post-state hashes produce a divergence")
    func differentPostHashProducesDivergence() {
        let expected = ReplayTrace(steps: [
            ReplayStep(preStateHash: "h1", postStateHash: "h2", actionName: "click", criticOutcome: .success),
        ])
        let actual = ReplayTrace(steps: [
            ReplayStep(preStateHash: "h1", postStateHash: "h3", actionName: "click", criticOutcome: .success),
        ])
        let divergences = engine.compare(expected: expected, actual: actual)
        #expect(divergences.count == 1)
        #expect(divergences[0].stepIndex == 0)
        #expect(divergences[0].expectedPostHash == "h2")
        #expect(divergences[0].actualPostHash == "h3")
    }

    @Test("Length mismatch is reported as a divergence")
    func lengthMismatchReported() {
        let short = ReplayTrace(steps: [
            ReplayStep(preStateHash: "h1", postStateHash: "h2", actionName: "click", criticOutcome: .success),
        ])
        let long = ReplayTrace(steps: [
            ReplayStep(preStateHash: "h1", postStateHash: "h2", actionName: "click", criticOutcome: .success),
            ReplayStep(preStateHash: "h2", postStateHash: "h3", actionName: "type", criticOutcome: .success),
        ])
        let divergences = engine.compare(expected: short, actual: long)
        #expect(divergences.count == 1)
        #expect(divergences[0].actionName == "length_mismatch")
    }

    // MARK: - ReplayTrace metrics

    @Test("ReplayTrace computes correct success rate")
    func traceSuccessRate() {
        let trace = ReplayTrace(steps: [
            ReplayStep(preStateHash: "h1", postStateHash: "h2", actionName: "a", criticOutcome: .success),
            ReplayStep(preStateHash: "h2", postStateHash: "h3", actionName: "b", criticOutcome: .failure),
            ReplayStep(preStateHash: "h3", postStateHash: "h4", actionName: "c", criticOutcome: .success),
        ])
        #expect(trace.stepCount == 3)
        #expect(trace.failureCount == 1)
        #expect(trace.successRate > 0.66)
        #expect(trace.successRate < 0.67)
    }

    @Test("Empty trace has zero success rate")
    func emptyTraceZeroSuccessRate() {
        let trace = ReplayTrace(steps: [])
        #expect(trace.successRate == 0)
        #expect(trace.failureCount == 0)
    }
}
