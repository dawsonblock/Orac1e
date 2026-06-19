import CoreGraphics
import Foundation
import Testing
@testable import OracleOS

@MainActor
@Suite("Core Contracts")
struct CoreContractsTests {

    @Test("UnifiedElement codable round trip")
    func unifiedElementRoundTrip() throws {
        let element = UnifiedElement(
            id: "element-1",
            source: .ax,
            role: "AXButton",
            label: "Send",
            value: nil,
            frame: CGRect(x: 10, y: 20, width: 100, height: 40),
            enabled: true,
            visible: true,
            focused: false,
            confidence: 0.9
        )

        let encoded = try JSONEncoder().encode(element)
        let decoded = try JSONDecoder().decode(UnifiedElement.self, from: encoded)

        #expect(decoded.id == element.id)
        #expect(decoded.label == element.label)
        #expect(decoded.frame == element.frame)
    }

    @Test("Observation hash is stable")
    func observationHashStable() {
        let element = UnifiedElement(id: "focused", source: .ax, label: "Body")
        let observation = Observation(
            app: "Notes",
            windowTitle: "Quick Note",
            url: nil,
            focusedElementID: "focused",
            elements: [element]
        )

        #expect(observation.stableHash() == observation.stableHash())
    }

    @Test("Action verifier checks focus and value")
    func actionVerifierChecks() {
        let send = UnifiedElement(id: "send", source: .ax, label: "Send")
        let field = UnifiedElement(
            id: "subject",
            source: .ax,
            label: "Subject",
            value: "Quarterly report",
            focused: true
        )
        let observation = Observation(
            app: "Chrome",
            windowTitle: "Compose",
            url: "https://mail.google.com/mail/u/0/#inbox?compose=new",
            focusedElementID: "subject",
            elements: [send, field]
        )

        let summary = ActionVerifier.verify(
            post: observation,
            conditions: [
                .elementFocused("subject"),
                .elementValueEquals("subject", "Quarterly report"),
                .elementAppeared("send")
            ]
        )

        #expect(summary.status == .passed)
        #expect(summary.checks.allSatisfy { $0.passed })
    }

    @Test("Action verifier matches query-based focus, app, window, and URL")
    func actionVerifierChecksContextConditions() {
        let field = UnifiedElement(
            id: "subject-id",
            source: .ax,
            role: "AXTextField",
            label: "Subject",
            value: "Quarterly report",
            focused: true
        )
        let observation = Observation(
            app: "Google Chrome",
            windowTitle: "Compose - Gmail",
            url: "https://mail.google.com/mail/u/0/#inbox?compose=new",
            focusedElementID: "subject-id",
            elements: [field]
        )

        let summary = ActionVerifier.verify(
            post: observation,
            conditions: [
                .elementFocused("Subject"),
                .appFrontmost("Chrome"),
                .windowTitleContains("Compose"),
                .urlContains("mail.google.com")
            ]
        )

        #expect(summary.status == .passed)
        #expect(summary.checks.allSatisfy { $0.passed })
    }

    @Test("Observation fusion prefers stronger sources and preserves confidence")
    func observationFusionPrefersStrongerSources() {
        let ax = UnifiedElement(
            id: "ax-send",
            source: .ax,
            role: "AXButton",
            label: "Send",
            frame: CGRect(x: 20, y: 30, width: 80, height: 24),
            confidence: 0.92
        )
        let cdp = UnifiedElement(
            id: "cdp-send",
            source: .cdp,
            role: "AXButton",
            label: "Send",
            frame: CGRect(x: 22, y: 31, width: 80, height: 24),
            confidence: 0.74
        )

        let fused = ObservationFusion.fuse(ax: [ax], cdp: [cdp], vision: [])

        #expect(fused.count == 1)
        #expect(fused[0].source == .fused)
        #expect(fused[0].label == "Send")
        #expect(fused[0].confidence == 0.92)
    }

    @Test("Planning state abstraction is stable across small observation drift")
    func planningStateStableAcrossDrift() {
        let abstraction = StateAbstraction()

        let firstObservation = Observation(
            app: "Google Chrome",
            windowTitle: "Inbox - Gmail",
            url: "https://mail.google.com/mail/u/0/#inbox",
            focusedElementID: "compose",
            elements: [
                UnifiedElement(id: "compose", source: .ax, role: "AXButton", label: "Compose", focused: true),
            ]
        )
        let secondObservation = Observation(
            app: "Google Chrome",
            windowTitle: "Inbox - Gmail",
            url: "https://mail.google.com/mail/u/0/#inbox?zx=123",
            focusedElementID: "compose-2",
            elements: [
                UnifiedElement(id: "compose-2", source: .ax, role: "AXButton", label: "Compose mail", focused: true),
            ]
        )

        let firstState = abstraction.abstract(
            observation: firstObservation,
            observationHash: ObservationHash.hash(firstObservation)
        )
        let secondState = abstraction.abstract(
            observation: secondObservation,
            observationHash: ObservationHash.hash(secondObservation)
        )

        #expect(firstState.id == secondState.id)
        #expect(firstState.navigationClass == "gmail")
    }

    @Test("Candidate graph accumulates repeated verified transitions")
    func candidateGraphAccumulatesTransitions() {
        let candidateGraph = CandidateGraph()
        let fromState = PlanningStateID(rawValue: "chrome|gmail|inbox")
        let toState = PlanningStateID(rawValue: "chrome|gmail|compose")
        let transition = VerifiedTransition(
            fromPlanningStateID: fromState,
            toPlanningStateID: toState,
            actionContractID: "click|AXButton|Compose|query",
            postconditionClass: .elementAppeared,
            verified: true,
            failureClass: nil,
            latencyMs: 120
        )

        candidateGraph.record(transition)
        candidateGraph.record(transition)

        #expect(candidateGraph.nodes[fromState]?.visitCount == 2)
        #expect(candidateGraph.edges.count == 1)
        #expect(candidateGraph.edges.values.first?.attempts == 2)
        #expect(candidateGraph.edges.values.first?.successes == 2)
    }

    @Test("Trace event codable round trip")
    func traceEventRoundTrip() throws {
        let result = ActionResult(
            success: true,
            verified: true,
            message: nil,
            method: "ax-native",
            verificationStatus: .passed,
            failureClass: nil,
            elapsedMs: 123
        )
        let event = TraceEvent(
            sessionID: "session-1",
            taskID: nil,
            stepID: 1,
            toolName: "oracle_click",
            actionName: "click",
            actionTarget: "Send",
            actionText: nil,
            selectedElementID: "send-button",
            selectedElementLabel: "Send",
            candidateScore: 0.99,
            candidateReasons: ["exact label match", "source trust"],
            preObservationHash: "pre",
            postObservationHash: "post",
            planningStateID: "gmail|compose",
            beliefSnapshotID: nil,
            postcondition: "element_appeared:Message sent",
            postconditionClass: "elementAppeared",
            actionContractID: "click|AXButton|Send|ax-native",
            executionMode: "verified-execution",
            verified: result.verified,
            success: result.success,
            failureClass: nil,
            recoveryStrategy: nil,
            recoverySource: nil,
            elapsedMs: result.elapsedMs,
            screenshotPath: nil,
            notes: nil
        )

        let encoder = OracleJSONCoding.makeEncoder()
        let encoded = try encoder.encode(event)

        let decoder = OracleJSONCoding.makeDecoder()
        let decoded = try decoder.decode(TraceEvent.self, from: encoded)

        #expect(decoded.sessionID == event.sessionID)
        #expect(decoded.actionName == "click")
        #expect(decoded.selectedElementID == "send-button")
        #expect(decoded.verified)
        #expect(decoded.elapsedMs == 123)
        #expect(decoded.schemaVersion == TraceSchemaVersion.current)
        #expect(decoded.planningStateID == "gmail|compose")
        #expect(decoded.actionContractID == "click|AXButton|Send|ax-native")
    }

    @Test("ActionResult encodes verification and elapsed time")
    func actionResultRoundTrip() throws {
        let result = ActionResult(
            success: true,
            verified: true,
            message: "Verified success",
            method: "ax-native",
            verificationStatus: .passed,
            failureClass: nil,
            elapsedMs: 42
        )

        let encoded = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: encoded)

        #expect(decoded.verified)
        #expect(decoded.elapsedMs == 42)
        #expect(decoded.method == "ax-native")
    }

    @Test("TraceEvent compatibility initializer still works")
    func traceEventCompatibilityInitializer() {
        let event = TraceEvent(action: "click _Applications_", success: true, message: "compat")

        #expect(event.sessionID == "compat")
        #expect(event.stepID == 0)
        #expect(event.actionName == "click _Applications_")
        #expect(event.success)
        #expect(event.verified)
        #expect(event.schemaVersion == TraceSchemaVersion.current)
        #expect(event.notes == "compat")
    }

    @Test("Legacy trace payloads still decode")
    func legacyTracePayloadDecode() throws {
        let legacyJSON = """
        {
          "timestamp": "2026-03-10T12:00:00Z",
          "action": "click Compose",
          "success": true,
          "message": "legacy trace"
        }
        """.data(using: .utf8)!

        let decoder = OracleJSONCoding.makeDecoder()
        let decoded = try decoder.decode(TraceEvent.self, from: legacyJSON)

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.sessionID == "legacy")
        #expect(decoded.stepID == 0)
        #expect(decoded.actionName == "click Compose")
        #expect(decoded.success)
        #expect(decoded.verified)
        #expect(decoded.notes == "legacy trace")
    }
}
