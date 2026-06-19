// CriticLoop.swift — Self-evaluation after every executed action.
//
// Every action must be followed by a critic pass.
//
//   Input:   state_before, action, state_after
//   Output:  SUCCESS | PARTIAL_SUCCESS | FAILURE | UNKNOWN
//
// The planner receives a recovery signal when the critic detects
// FAILURE or UNKNOWN, closing the observe→plan→execute→evaluate
// feedback loop.

import Foundation

// MARK: - Outcome classification

/// Result of the critic's evaluation of a single action step.
public enum CriticOutcome: String, Sendable, Codable, CaseIterable {
    /// Expected state change observed.
    case success
    /// Some expected changes observed, but not all.
    case partialSuccess = "partial_success"
    /// Expected state change did not occur.
    case failure
    /// Unable to determine outcome.
    case unknown
}

// MARK: - Critic verdict

/// Full verdict produced by the critic for one execution step.
public struct CriticVerdict: Sendable, Codable {
    public let outcome: CriticOutcome
    public let preStateHash: String
    public let postStateHash: String
    public let actionName: String
    public let stateChanged: Bool
    public let expectedConditionsMet: Int
    public let expectedConditionsTotal: Int
    public let notes: [String]
    public let timestamp: TimeInterval

    public init(
        outcome: CriticOutcome,
        preStateHash: String,
        postStateHash: String,
        actionName: String,
        stateChanged: Bool,
        expectedConditionsMet: Int = 0,
        expectedConditionsTotal: Int = 0,
        notes: [String] = [],
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.outcome = outcome
        self.preStateHash = preStateHash
        self.postStateHash = postStateHash
        self.actionName = actionName
        self.stateChanged = stateChanged
        self.expectedConditionsMet = expectedConditionsMet
        self.expectedConditionsTotal = expectedConditionsTotal
        self.notes = notes
        self.timestamp = timestamp
    }

    /// Whether recovery should be triggered.
    public var needsRecovery: Bool {
        outcome == .failure || outcome == .unknown
    }

    public func toDict() -> [String: Any] {
        [
            "outcome": outcome.rawValue,
            "pre_state_hash": preStateHash,
            "post_state_hash": postStateHash,
            "action_name": actionName,
            "state_changed": stateChanged,
            "expected_conditions_met": expectedConditionsMet,
            "expected_conditions_total": expectedConditionsTotal,
            "needs_recovery": needsRecovery,
            "notes": notes,
            "timestamp": timestamp,
        ]
    }
}

// MARK: - Critic

/// Evaluates every executed action by comparing pre- and post-state,
/// checking postconditions from the action's ``ActionSchema``, and
/// classifying the outcome.
///
/// Usage:
///
///     let critic = CriticLoop()
///     let verdict = critic.evaluate(
///         preState: ..., postState: ...,
///         schema: ..., actionResult: ...
///     )
///     if verdict.needsRecovery { /* trigger recovery planner */ }
///
// MARK: - Multi-signal extension

/// Additional evidence signals the critic can consume beyond CompressedUIState diffs.
///
/// Providing more signals allows the critic to produce better-calibrated outcomes.
/// All signals are optional; passing an empty array is identical to calling the
/// single-argument `evaluate` variant.
public enum CriticSignal: Sendable {
    /// A semantic world-state diff produced by ``StateDiffEngine``.
    case stateDiff(StateDiff)
    /// True/false result of a semantic property validation check.
    /// - Parameters:
    ///   - description: Human-readable description of the check.
    ///   - passed: Whether the semantic condition passed.
    case semanticValidation(description: String, passed: Bool)
    /// Result of a UI element presence / state check.
    /// - Parameters:
    ///   - identifier: Accessibility label or element ID.
    ///   - passed: Whether the expected UI state was observed.
    case uiElementCheck(identifier: String, passed: Bool)
    /// Character-level diff summary for file-mutation actions.
    /// - Parameters:
    ///   - relativePath: Workspace-relative file path.
    ///   - hasChanges: Whether the file content changed after the action.
    case fileDiff(relativePath: String, hasChanges: Bool)
}

// MARK: - CriticLoop

public struct CriticLoop: Sendable {
    /// How many consecutive `.unknown` verdicts are tolerated before
    /// the critic upgrades the outcome to `.failure`. This prevents the
    /// agent from silently drifting through a long run of unverifiable steps.
    public let maxConsecutiveUnknown: Int

    private var consecutiveUnknownCount: Int = 0

    public init(maxConsecutiveUnknown: Int = 3) {
        self.maxConsecutiveUnknown = maxConsecutiveUnknown
    }

    /// Record the verdict and apply consecutive-unknown escalation.
    /// Returns the (potentially upgraded) verdict.
    private mutating func tracked(_ verdict: CriticVerdict) -> CriticVerdict {
        if verdict.outcome == .unknown {
            consecutiveUnknownCount += 1
            if consecutiveUnknownCount > maxConsecutiveUnknown {
                return CriticVerdict(
                    outcome: .failure,
                    preStateHash: verdict.preStateHash,
                    postStateHash: verdict.postStateHash,
                    actionName: verdict.actionName,
                    stateChanged: verdict.stateChanged,
                    expectedConditionsMet: verdict.expectedConditionsMet,
                    expectedConditionsTotal: verdict.expectedConditionsTotal,
                    notes: verdict.notes + ["consecutive-unknown threshold reached (\(consecutiveUnknownCount)); escalated to failure"],
                    timestamp: verdict.timestamp
                )
            }
        } else {
            consecutiveUnknownCount = 0
        }
        return verdict
    }

    // MARK: - Fast-path: ActionResult only

    /// Evaluate an action using only the ``ActionResult`` when no UI state
    /// snapshot is available (e.g., code actions, background tasks).
    ///
    /// - Returns: A ``CriticVerdict`` based solely on executor-reported flags.
    public mutating func evaluateActionResult(
        _ result: ActionResult,
        actionName: String
    ) -> CriticVerdict {
        let hash = "no-state"
        if result.blockedByPolicy {
            return tracked(CriticVerdict(
                outcome: .failure,
                preStateHash: hash,
                postStateHash: hash,
                actionName: actionName,
                stateChanged: false,
                notes: ["action blocked by policy"]
            ))
        }
        if !result.executedThroughExecutor {
            return tracked(CriticVerdict(
                outcome: .failure,
                preStateHash: hash,
                postStateHash: hash,
                actionName: actionName,
                stateChanged: false,
                notes: ["trust boundary violation: action did not pass through VerifiedExecutor.execute"]
            ))
        }
        let outcome: CriticOutcome = result.verified ? .success : (result.success ? .partialSuccess : .failure)
        return tracked(CriticVerdict(
            outcome: outcome,
            preStateHash: hash,
            postStateHash: hash,
            actionName: actionName,
            stateChanged: result.success,
            notes: result.message.map { [$0] } ?? []
        ))
    }

    /// Evaluate a single action step.
    ///
    /// - Parameters:
    ///   - preState: Compressed UI state *before* the action.
    ///   - postState: Compressed UI state *after* the action.
    ///   - schema: The ``ActionSchema`` that was executed (may be nil for
    ///     actions that do not yet have schemas).
    ///   - actionResult: The ``ActionResult`` from the executor.
    /// - Returns: A ``CriticVerdict`` classifying the outcome.
    public mutating func evaluate(
        preState: CompressedUIState,
        postState: CompressedUIState,
        schema: ActionSchema?,
        actionResult: ActionResult
    ) -> CriticVerdict {
        let preHash = stateFingerprint(preState)
        let postHash = stateFingerprint(postState)
        let stateChanged = preHash != postHash

        // If the executor already reports policy-blocked or hard failure,
        // short-circuit.
        if actionResult.blockedByPolicy {
            return tracked(CriticVerdict(
                outcome: .failure,
                preStateHash: preHash,
                postStateHash: postHash,
                actionName: schema?.name ?? "unknown",
                stateChanged: stateChanged,
                notes: ["action blocked by policy"]
            ))
        }

        if !actionResult.success {
            return tracked(CriticVerdict(
                outcome: .failure,
                preStateHash: preHash,
                postStateHash: postHash,
                actionName: schema?.name ?? "unknown",
                stateChanged: stateChanged,
                notes: [actionResult.message ?? "action failed"]
            ))
        }

        // If no schema is attached we can only do hash-level evaluation.
        guard let schema else {
            let outcome: CriticOutcome = stateChanged ? .success : .unknown
            return tracked(CriticVerdict(
                outcome: outcome,
                preStateHash: preHash,
                postStateHash: postHash,
                actionName: "unknown",
                stateChanged: stateChanged,
                notes: stateChanged ? ["state changed"] : ["no schema; state unchanged"]
            ))
        }

        // Check expected postconditions against postState.
        let (met, total, notes) = checkPostconditions(
            schema.expectedPostconditions,
            in: postState
        )

        let outcome = classifyOutcome(
            stateChanged: stateChanged,
            conditionsMet: met,
            conditionsTotal: total,
            actionSuccess: actionResult.success,
            verified: actionResult.verified,
            executedThroughExecutor: actionResult.executedThroughExecutor
        )

        return tracked(CriticVerdict(
            outcome: outcome,
            preStateHash: preHash,
            postStateHash: postHash,
            actionName: schema.name,
            stateChanged: stateChanged,
            expectedConditionsMet: met,
            expectedConditionsTotal: total,
            notes: notes
        ))
    }

    /// Evaluate an action step using multi-signal evidence.
    ///
    /// The critic synthesizes state diffs, file diffs, UI signal checks, and
    /// semantic validations into a unified verdict. This overload should be
    /// preferred whenever the executor can provide extended evidence.
    ///
    /// - Parameters:
    ///   - preState: Compressed UI state *before* the action.
    ///   - postState: Compressed UI state *after* the action.
    ///   - schema: The ``ActionSchema`` executed.
    ///   - actionResult: The base success/failure report from the executor.
    ///   - signals: Array of heterogeneous ``CriticSignal`` evidence blocks.
    /// - Returns: A calibrated ``CriticVerdict``.
    public mutating func evaluate(
        preState: CompressedUIState,
        postState: CompressedUIState,
        schema: ActionSchema?,
        actionResult: ActionResult,
        signals: [CriticSignal]
    ) -> CriticVerdict {
        // If no extended signals are provided, fall back to the base evaluation.
        if signals.isEmpty {
            return evaluate(
                preState: preState,
                postState: postState,
                schema: schema,
                actionResult: actionResult
            )
        }

        let preHash = stateFingerprint(preState)
        let postHash = stateFingerprint(postState)
        
        var stateChanged = preHash != postHash
        var positiveEvidence = 0
        var negativeEvidence = 0
        var evidenceNotes: [String] = []

        // Process all provided signals
        for signal in signals {
            switch signal {
            case .stateDiff(let diff):
                if diff.changeCount > 0 {
                    stateChanged = true
                    positiveEvidence += 1
                    evidenceNotes.append("semantic state diff observed (\(diff.changeCount) changes)")
                }
            case .fileDiff(let path, let hasChanges):
                if hasChanges {
                    stateChanged = true
                    positiveEvidence += 1
                    evidenceNotes.append("file mutation verified at \(path)")
                } else {
                    evidenceNotes.append("no file mutation observed at \(path)")
                }
            case .semanticValidation(let desc, let passed):
                if passed {
                    positiveEvidence += 1
                    evidenceNotes.append("semantic validation passed: \(desc)")
                } else {
                    negativeEvidence += 1
                    evidenceNotes.append("semantic validation failed: \(desc)")
                }
            case .uiElementCheck(let id, let passed):
                if passed {
                    positiveEvidence += 1
                    evidenceNotes.append("UI element \(id) verified")
                } else {
                    negativeEvidence += 1
                    evidenceNotes.append("UI element \(id) missing or incorrect")
                }
            }
        }

        if actionResult.blockedByPolicy {
            return CriticVerdict(
                outcome: .failure,
                preStateHash: preHash,
                postStateHash: postHash,
                actionName: schema?.name ?? "unknown",
                stateChanged: stateChanged,
                notes: ["action blocked by policy"] + evidenceNotes
            )
        }

        guard let schema else {
            // Un-schema'd actions rely purely on the signal consensus.
            let outcome: CriticOutcome = (positiveEvidence > negativeEvidence || (stateChanged && negativeEvidence == 0)) ? .success : .unknown
            return CriticVerdict(
                outcome: outcome,
                preStateHash: preHash,
                postStateHash: postHash,
                actionName: "unknown",
                stateChanged: stateChanged,
                notes: evidenceNotes + (stateChanged ? ["state changed"] : ["no schema; state unchanged"])
            )
        }

        // Schema is present; check explicit postconditions as the baseline ...
        let (met, total, baselineNotes) = checkPostconditions(
            schema.expectedPostconditions,
            in: postState
        )

        let baselineOutcome = classifyOutcome(
            stateChanged: stateChanged,
            conditionsMet: met,
            conditionsTotal: total,
            actionSuccess: actionResult.success,
            verified: actionResult.verified,
            executedThroughExecutor: actionResult.executedThroughExecutor
        )

        // ... then adjust based on strong signal evidence.
        let finalOutcome: CriticOutcome
        let strongNegativeSignal = negativeEvidence > 0
        let strongPositiveSignal = positiveEvidence > 0 && negativeEvidence == 0

        if strongNegativeSignal {
            finalOutcome = .failure // Hard signals override weak UI inference.
        } else if baselineOutcome == .unknown && strongPositiveSignal {
            finalOutcome = .success
        } else {
            finalOutcome = baselineOutcome
        }

        return tracked(CriticVerdict(
            outcome: finalOutcome,
            preStateHash: preHash,
            postStateHash: postHash,
            actionName: schema.name,
            stateChanged: stateChanged,
            expectedConditionsMet: met,
            expectedConditionsTotal: total,
            notes: evidenceNotes + baselineNotes
        ))
    }

    // MARK: - Internal

    /// Classify the overall outcome from evidence.
    func classifyOutcome(
        stateChanged: Bool,
        conditionsMet: Int,
        conditionsTotal: Int,
        actionSuccess: Bool,
        verified: Bool,
        executedThroughExecutor: Bool = true
    ) -> CriticOutcome {
        // Actions that bypassed the verified executor are untrustworthy.
        if !executedThroughExecutor {
            return .failure
        }
        // If postconditions are declared, use them as ground truth.
        if conditionsTotal > 0 {
            if conditionsMet == conditionsTotal { return .success }
            if conditionsMet > 0 { return .partialSuccess }
            return .failure
        }
        // No postconditions declared — fall back to state diff + executor verdict.
        if verified { return .success }
        if actionSuccess && stateChanged { return .success }
        // A successful action that produced no state change is a soft stall:
        // treat it as failure rather than unknown so the planner gets a clear
        // recovery signal rather than silently continuing.
        if actionSuccess && !stateChanged { return .failure }
        return .failure
    }

    /// Check each expected postcondition against the post state.
    func checkPostconditions(
        _ conditions: [SchemaCondition],
        in state: CompressedUIState
    ) -> (met: Int, total: Int, notes: [String]) {
        guard !conditions.isEmpty else { return (0, 0, []) }
        var met = 0
        var notes: [String] = []

        for condition in conditions {
            switch condition {
            case .elementExists(let kind, let label):
                if state.elements.contains(where: { $0.kind == kind && $0.label == label }) {
                    met += 1
                } else {
                    notes.append("missing \(kind.rawValue)(\(label))")
                }
            case .appFrontmost(let app):
                if state.app == app {
                    met += 1
                } else {
                    notes.append("app not frontmost: \(app)")
                }
            case .windowTitleContains(let value):
                if let title = state.windowTitle, title.contains(value) {
                    met += 1
                } else {
                    notes.append("window title missing: \(value)")
                }
            case .urlContains(let value):
                if let url = state.url, url.contains(value) {
                    met += 1
                } else {
                    notes.append("url missing: \(value)")
                }
            case .valueEquals(let label, let expected):
                // Cannot verify from CompressedUIState alone.
                notes.append("value check skipped for \(label)=\(expected)")
            case .custom(let description):
                // Custom predicates require external evaluation.
                notes.append("custom check skipped: \(description)")
            }
        }
        return (met, conditions.count, notes)
    }

    /// Simple fingerprint for change detection.
    func stateFingerprint(_ state: CompressedUIState) -> String {
        let parts = state.elements.map { "\($0.kind.rawValue)|\($0.label)" }
        let joined = parts.sorted().joined(separator: ";")
        let appPart = state.app ?? ""
        let titlePart = state.windowTitle ?? ""
        return "\(appPart)|\(titlePart)|\(joined)"
    }
}
