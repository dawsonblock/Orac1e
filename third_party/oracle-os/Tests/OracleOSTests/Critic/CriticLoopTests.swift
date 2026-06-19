import Foundation
import Testing
@testable import OracleOS

@Suite("Critic Loop")
struct CriticLoopTests {

    let critic = CriticLoop()

    // MARK: - Outcome classification

    @Test("Critic returns success when postconditions met")
    func successWhenPostconditionsMet() {
        let preState = CompressedUIState(
            app: "Slack",
            elements: [
                SemanticElement(id: "input-1", kind: .input, label: "Message"),
            ]
        )
        let postState = CompressedUIState(
            app: "Slack",
            elements: [
                SemanticElement(id: "input-1", kind: .input, label: "Message"),
                SemanticElement(id: "msg-1", kind: .text, label: "hello"),
            ]
        )
        let schema = ActionSchema(
            name: "click_Send",
            kind: .click,
            expectedPostconditions: [
                .elementExists(kind: .text, label: "hello"),
            ]
        )
        let result = ActionResult(success: true, verified: true)

        let verdict = critic.evaluate(
            preState: preState,
            postState: postState,
            schema: schema,
            actionResult: result
        )

        #expect(verdict.outcome == .success)
        #expect(verdict.stateChanged == true)
        #expect(!verdict.needsRecovery)
    }

    @Test("Critic returns failure when postconditions not met")
    func failureWhenPostconditionsNotMet() {
        let preState = CompressedUIState(
            app: "Slack",
            elements: [
                SemanticElement(id: "input-1", kind: .input, label: "Message"),
            ]
        )
        let postState = CompressedUIState(
            app: "Slack",
            elements: [
                SemanticElement(id: "input-1", kind: .input, label: "Message"),
            ]
        )
        let schema = ActionSchema(
            name: "click_Send",
            kind: .click,
            expectedPostconditions: [
                .elementExists(kind: .text, label: "hello"),
            ]
        )
        let result = ActionResult(success: true, verified: false)

        let verdict = critic.evaluate(
            preState: preState,
            postState: postState,
            schema: schema,
            actionResult: result
        )

        #expect(verdict.outcome == .failure)
        #expect(verdict.needsRecovery)
        #expect(verdict.notes.contains(where: { $0.contains("missing") }))
    }

    @Test("Critic returns partial success when some conditions met")
    func partialSuccessWhenSomeConditionsMet() {
        let preState = CompressedUIState(app: "Safari", elements: [])
        let postState = CompressedUIState(
            app: "Safari",
            elements: [
                SemanticElement(id: "btn-1", kind: .button, label: "OK"),
            ]
        )
        let schema = ActionSchema(
            name: "test_action",
            kind: .click,
            expectedPostconditions: [
                .elementExists(kind: .button, label: "OK"),
                .elementExists(kind: .text, label: "Confirmed"),
            ]
        )
        let result = ActionResult(success: true, verified: false)

        let verdict = critic.evaluate(
            preState: preState,
            postState: postState,
            schema: schema,
            actionResult: result
        )

        #expect(verdict.outcome == .partialSuccess)
        #expect(verdict.expectedConditionsMet == 1)
        #expect(verdict.expectedConditionsTotal == 2)
    }

    // MARK: - Edge cases

    @Test("Critic returns failure when action blocked by policy")
    func failureWhenBlockedByPolicy() {
        let state = CompressedUIState(app: "Finder", elements: [])
        let result = ActionResult(
            success: false,
            verified: false,
            blockedByPolicy: true
        )

        let verdict = critic.evaluate(
            preState: state,
            postState: state,
            schema: nil,
            actionResult: result
        )

        #expect(verdict.outcome == .failure)
        #expect(verdict.needsRecovery)
        #expect(verdict.notes.contains(where: { $0.contains("policy") }))
    }

    @Test("Critic returns failure when action reports failure")
    func failureWhenActionFails() {
        let state = CompressedUIState(app: "Safari", elements: [])
        let result = ActionResult(
            success: false,
            verified: false,
            message: "element not found"
        )

        let verdict = critic.evaluate(
            preState: state,
            postState: state,
            schema: nil,
            actionResult: result
        )

        #expect(verdict.outcome == .failure)
        #expect(verdict.needsRecovery)
    }

    @Test("Critic returns unknown when no schema and no state change")
    func unknownWithoutSchemaAndNoChange() {
        let state = CompressedUIState(
            app: "Safari",
            elements: [
                SemanticElement(id: "1", kind: .button, label: "OK"),
            ]
        )
        let result = ActionResult(success: true, verified: false)

        let verdict = critic.evaluate(
            preState: state,
            postState: state,
            schema: nil,
            actionResult: result
        )

        #expect(verdict.outcome == .unknown)
    }

    @Test("Critic returns success when no schema but state changed")
    func successWithoutSchemaButStateChanged() {
        let preState = CompressedUIState(app: "Safari", elements: [])
        let postState = CompressedUIState(
            app: "Safari",
            elements: [
                SemanticElement(id: "1", kind: .button, label: "OK"),
            ]
        )
        let result = ActionResult(success: true, verified: false)

        let verdict = critic.evaluate(
            preState: preState,
            postState: postState,
            schema: nil,
            actionResult: result
        )

        #expect(verdict.outcome == .success)
        #expect(verdict.stateChanged == true)
    }

    // MARK: - State fingerprinting

    @Test("State fingerprint changes when elements change")
    func fingerprintChangesWithElements() {
        let state1 = CompressedUIState(
            app: "Safari",
            elements: [SemanticElement(id: "1", kind: .button, label: "OK")]
        )
        let state2 = CompressedUIState(
            app: "Safari",
            elements: [SemanticElement(id: "2", kind: .input, label: "Search")]
        )
        let fp1 = critic.stateFingerprint(state1)
        let fp2 = critic.stateFingerprint(state2)

        #expect(fp1 != fp2)
    }

    @Test("State fingerprint stable for same elements")
    func fingerprintStableForSameElements() {
        let state1 = CompressedUIState(
            app: "Safari",
            elements: [SemanticElement(id: "1", kind: .button, label: "OK")]
        )
        let state2 = CompressedUIState(
            app: "Safari",
            elements: [SemanticElement(id: "2", kind: .button, label: "OK")]
        )
        let fp1 = critic.stateFingerprint(state1)
        let fp2 = critic.stateFingerprint(state2)

        #expect(fp1 == fp2)
    }

    // MARK: - Verdict serialization

    @Test("CriticVerdict toDict includes all fields")
    func verdictToDict() {
        let verdict = CriticVerdict(
            outcome: .success,
            preStateHash: "abc",
            postStateHash: "def",
            actionName: "click_Send",
            stateChanged: true,
            expectedConditionsMet: 1,
            expectedConditionsTotal: 1,
            notes: ["ok"]
        )
        let dict = verdict.toDict()

        #expect(dict["outcome"] as? String == "success")
        #expect(dict["action_name"] as? String == "click_Send")
        #expect(dict["state_changed"] as? Bool == true)
        #expect(dict["needs_recovery"] as? Bool == false)
    }

    // MARK: - CriticOutcome

    @Test("CriticOutcome covers all expected cases")
    func outcomeCoversAllCases() {
        let allCases = CriticOutcome.allCases
        #expect(allCases.contains(.success))
        #expect(allCases.contains(.partialSuccess))
        #expect(allCases.contains(.failure))
        #expect(allCases.contains(.unknown))
        #expect(allCases.count == 4)
    }
}
