import Foundation
import Testing
@testable import OracleOS

@Suite("Failure Classifier")
struct FailureClassifierTests {

    @Test("Classifies target missing from error description")
    func classifiesTargetMissing() {
        let result = FailureClassifier.classify(errorDescription: "Target element not found in the page")
        #expect(result.failureClass == .targetMissing)
        #expect(result.confidence > 0.5)
    }

    @Test("Classifies ambiguous target")
    func classifiesAmbiguousTarget() {
        let result = FailureClassifier.classify(errorDescription: "Ambiguous element match on the page")
        #expect(result.failureClass == .elementAmbiguous)
    }

    @Test("Classifies wrong window focus")
    func classifiesWrongFocus() {
        let result = FailureClassifier.classify(errorDescription: "Wrong focus - expected Safari but found Finder")
        #expect(result.failureClass == .wrongFocus)
    }

    @Test("Classifies unexpected dialog")
    func classifiesUnexpectedDialog() {
        let result = FailureClassifier.classify(errorDescription: "Unexpected dialog appeared blocking the action")
        #expect(result.failureClass == .unexpectedDialog)
    }

    @Test("Classifies permission blocked")
    func classifiesPermissionBlocked() {
        let result = FailureClassifier.classify(errorDescription: "Permission denied for file access")
        #expect(result.failureClass == .permissionBlocked)
    }

    @Test("Classifies patch failure")
    func classifiesPatchFailure() {
        let result = FailureClassifier.classify(errorDescription: "Patch application failed - rejected by git")
        #expect(result.failureClass == .patchApplyFailed)
    }

    @Test("Classifies environment mismatch")
    func classifiesEnvironmentMismatch() {
        let result = FailureClassifier.classify(errorDescription: "Environment mismatch detected")
        #expect(result.failureClass == .environmentMismatch)
    }

    @Test("Falls back to actionFailed for unrecognized errors")
    func fallsBackToActionFailed() {
        let result = FailureClassifier.classify(errorDescription: "Something completely unexpected happened")
        #expect(result.failureClass == .actionFailed)
        #expect(result.confidence < 0.5)
    }

    @Test("Classification confidence is bounded")
    func classificationConfidenceIsBounded() {
        let result = FailureClassifier.classify(errorDescription: "Target missing from view")
        #expect(result.confidence >= 0)
        #expect(result.confidence <= 1)
    }

    @Test("Classifies workflow replay failure")
    func classifiesWorkflowReplayFailure() {
        let result = FailureClassifier.classify(errorDescription: "Workflow replay failed to complete successfully")
        #expect(result.failureClass == .workflowReplayFailure)
        #expect(result.confidence > 0.5)
    }

    @Test("Context boosts confidence for repeated failure class")
    func contextBoostsConfidence() {
        let base = FailureClassifier.classify(errorDescription: "Target not found")
        let boosted = FailureClassifier.classify(
            errorDescription: "Target not found",
            context: FailureClassifierContext(recentFailureClasses: [.targetMissing])
        )
        #expect(boosted.confidence >= base.confidence)
    }
}
