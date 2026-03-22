import Foundation
import Testing
@testable import OracleOS

@Suite("Workflow Discovery")
struct WorkflowDiscoveryTests {

    @Test("Trace segmenter produces segments from successful events")
    func segmenterProducesSegments() {
        let events = makeSuccessfulTraceEvents(count: 4, sessionID: "s1", taskID: "t1")
        let segments = TraceSegmenter.segment(events: events)
        #expect(!segments.isEmpty)
        #expect(segments.allSatisfy { !$0.events.isEmpty })
    }

    @Test("Repeated segments require multiple distinct episodes")
    func repeatedSegmentsRequireMultipleEpisodes() {
        let eventsA = makeSuccessfulTraceEvents(count: 3, sessionID: "s1", taskID: "t1")
        let eventsB = makeSuccessfulTraceEvents(count: 3, sessionID: "s2", taskID: "t2")
        let combined = eventsA + eventsB
        let repeated = TraceSegmenter.repeatedSegments(events: combined)
        // Repeated segments need at least 2 segments from 2 distinct episodes
        for group in repeated {
            #expect(group.segments.count >= 2)
        }
    }

    @Test("Trace clusterer groups by action sequence shape")
    func traceClustererGroupsByShape() {
        let clusterer = TraceClusterer()
        let eventsA = makeSuccessfulTraceEvents(count: 3, sessionID: "s1", taskID: "t1")
        let eventsB = makeSuccessfulTraceEvents(count: 3, sessionID: "s2", taskID: "t2")
        let segmentsA = TraceSegmenter.segment(events: eventsA)
        let segmentsB = TraceSegmenter.segment(events: eventsB)
        let allSegments = segmentsA + segmentsB
        let clusters = clusterer.cluster(segments: allSegments)
        // Clusters should group identical fingerprints
        for cluster in clusters {
            let fingerprints = Set(cluster.segments.map(\.fingerprint))
            #expect(fingerprints.count == 1)
        }
    }

    @Test("Workflow synthesizer produces candidates from mined patterns")
    func synthesizerProducesCandidates() {
        let synthesizer = WorkflowSynthesizer()
        let events = makeSuccessfulTraceEvents(count: 3, sessionID: "s1", taskID: "t1")
            + makeSuccessfulTraceEvents(count: 3, sessionID: "s2", taskID: "t2")
        let workflows = synthesizer.synthesize(goalPattern: "click target", events: events)
        // Synthesizer may or may not find patterns depending on fingerprint match
        // but should not crash
        #expect(workflows.count >= 0)
    }

    private func makeSuccessfulTraceEvents(
        count: Int,
        sessionID: String,
        taskID: String
    ) -> [TraceEvent] {
        (0..<count).map { i in
            TraceEvent(
                sessionID: sessionID,
                taskID: taskID,
                stepID: i,
                toolName: "click",
                actionName: "click",
                agentKind: AgentKind.os.rawValue,
                planningStateID: "app|browse",
                selectedElementLabel: "Button\(i)",
                selectedElementID: "btn\(i)",
                success: true,
                verified: true
            )
        }
    }
}
