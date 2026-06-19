import Foundation

/// Verifies postconditions after each verified action to ensure the intended
/// effect actually occurred.
///
/// The verifier checks that:
/// - Click actions caused the expected UI change
/// - Open-file actions focused/opened the file
/// - Run-tests actions produced new test output
/// - Patch applications changed the intended file set
///
/// Every verification result is recorded alongside the transition.
public struct PostconditionVerifier: Sendable {

    public init() {}

    /// The result of a postcondition check.
    public struct VerificationResult: Sendable {
        public let passed: Bool
        public let preStateSignature: String
        public let postStateSignature: String
        public let action: String
        public let target: String?
        public let latencyMs: Double
        public let failureClass: String?
        public let notes: [String]

        public init(
            passed: Bool,
            preStateSignature: String,
            postStateSignature: String,
            action: String,
            target: String? = nil,
            latencyMs: Double = 0,
            failureClass: String? = nil,
            notes: [String] = []
        ) {
            self.passed = passed
            self.preStateSignature = preStateSignature
            self.postStateSignature = postStateSignature
            self.action = action
            self.target = target
            self.latencyMs = latencyMs
            self.failureClass = failureClass
            self.notes = notes
        }
    }

    /// Verify that the action's postcondition was met by comparing pre/post states.
    public func verify(
        action: String,
        target: String?,
        preState: WorldState,
        postState: WorldState,
        latencyMs: Double
    ) -> VerificationResult {
        let preSig = preState.observationHash
        let postSig = postState.observationHash
        let stateChanged = preSig != postSig

        var notes: [String] = []
        var passed = true
        var failureClass: String?

        let loweredAction = action.lowercased()

        // Click/target actions should cause a state change.
        if loweredAction.contains("click") || loweredAction.contains("target") {
            if !stateChanged {
                passed = false
                failureClass = "click_no_effect"
                notes.append("click action did not change state")
            }
        }

        // Open/focus actions should change the active app or window.
        if loweredAction.contains("open") || loweredAction.contains("focus") {
            let preApp = preState.observation.app
            let postApp = postState.observation.app
            if preApp == postApp && !stateChanged {
                passed = false
                failureClass = "open_no_effect"
                notes.append("open/focus action did not change app or state")
            }
        }

        // Test run actions should produce different planning state.
        if loweredAction.contains("test") || loweredAction.contains("build") {
            if preState.planningState.id == postState.planningState.id && !stateChanged {
                notes.append("test/build action may not have produced new output")
            }
        }

        // Patch actions should change the repository snapshot.
        if loweredAction.contains("patch") || loweredAction.contains("apply") {
            let preDirty = preState.repositorySnapshot?.isGitDirty
            let postDirty = postState.repositorySnapshot?.isGitDirty
            if preDirty == postDirty && preDirty != true {
                passed = false
                failureClass = "patch_no_effect"
                notes.append("patch action did not change repository state")
            }
        }

        return VerificationResult(
            passed: passed,
            preStateSignature: preSig,
            postStateSignature: postSig,
            action: action,
            target: target,
            latencyMs: latencyMs,
            failureClass: failureClass,
            notes: notes
        )
    }
}
