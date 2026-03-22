import Foundation

public struct EnvironmentMonitor: Sendable {
    public init() {}

    /// Detects discrepancies between the latest observed world state and the
    /// expected postconditions.
    ///
    /// Returns a `StateDelta` describing expectation mismatches relative to
    /// the latest observation if a mismatch is found, or `nil` when the
    /// environment matches expectations.
    public func detectChanges(between latest: WorldState, and expected: ExpectationModel) -> StateDelta? {
        var mismatches: [String] = []

        // App check: verify the expected application is frontmost.
        if let expectedApp = expected.expectedApp {
            if let currentApp = latest.observation.app {
                if !currentApp.localizedCaseInsensitiveContains(expectedApp) {
                    mismatches.append("expected_app:\(expectedApp)")
                }
            } else {
                // Missing observation for app when an expectation is set.
                mismatches.append("expected_app:\(expectedApp)")
            }
        }

        // Element check: verify expected elements are present in the observation.
        let observedLabels = Set(latest.observation.elements.compactMap(\.label))
        for element in expected.expectedElements {
            if !observedLabels.contains(where: { $0.localizedCaseInsensitiveContains(element) }) {
                mismatches.append("missing_element:\(element)")
            }
        }

        // URL check.
        if let expectedURL = expected.expectedURL {
            if let currentURL = latest.observation.url {
                if !currentURL.localizedCaseInsensitiveContains(expectedURL) {
                    mismatches.append("expected_url:\(expectedURL)")
                }
            } else {
                // Missing observation for URL when an expectation is set.
                mismatches.append("expected_url:\(expectedURL)")
            }
        }

        // Window title check.
        if let expectedWindow = expected.expectedWindowTitle {
            if let currentTitle = latest.observation.windowTitle {
                if !currentTitle.localizedCaseInsensitiveContains(expectedWindow) {
                    mismatches.append("expected_window:\(expectedWindow)")
                }
            } else {
                // Missing observation for window title when an expectation is set.
                mismatches.append("expected_window:\(expectedWindow)")
            }
        }

        guard !mismatches.isEmpty else { return nil }

        // This delta represents expectation mismatches against the latest
        // observation, not a diff from a concrete prior state. We therefore
        // leave `previousStateHash` empty and only report the current hash.
        return StateDelta(
            previousStateHash: "",
            currentStateHash: latest.observationHash,
            changedElements: mismatches
        )
    }

    /// Reconciles the world state after an action by checking the result
    /// postconditions against the provided `worldState`. Returns `true` if the
    /// environment is consistent.
    public func reconcile(
        worldState: WorldState,
        postconditions: [Postcondition]
    ) -> ReconciliationResult {
        var passed: [String] = []
        var failed: [String] = []

        for pc in postconditions {
            let ok = ActionVerifier.verify(post: worldState.observation, condition: pc)
            if ok {
                passed.append(pc.kind.rawValue + ":" + pc.target)
            } else {
                failed.append(pc.kind.rawValue + ":" + pc.target)
            }
        }

        return ReconciliationResult(
            consistent: failed.isEmpty,
            passedChecks: passed,
            failedChecks: failed,
            stateHash: worldState.observationHash
        )
    }
}

/// Result of a reconciliation check.
public struct ReconciliationResult: Sendable {
    public let consistent: Bool
    public let passedChecks: [String]
    public let failedChecks: [String]
    public let stateHash: String

    public init(consistent: Bool, passedChecks: [String], failedChecks: [String], stateHash: String) {
        self.consistent = consistent
        self.passedChecks = passedChecks
        self.failedChecks = failedChecks
        self.stateHash = stateHash
    }
}
