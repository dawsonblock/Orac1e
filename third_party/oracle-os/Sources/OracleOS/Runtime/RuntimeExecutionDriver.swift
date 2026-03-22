import Foundation

/// Bridges the AgentLoop execution path to the IntentAPI spine.
///
/// Translates ActionIntent → Intent → submitIntent, routing all execution
/// through the IntentAPI-based RuntimeOrchestrator.
@MainActor
public final class RuntimeExecutionDriver: AgentExecutionDriver {
    private final class SubmissionState: @unchecked Sendable {
        var result: ToolResult

        init(result: ToolResult) {
            self.result = result
        }
    }

    private let surface: RuntimeSurface
    private let intentAPI: any IntentAPI
    private static let submissionTimeoutSeconds: TimeInterval = 60

    /// Preferred init — translates ActionIntent to Intent and submits via IntentAPI.
    /// This is a pure translator: it converts external input into Intent and forwards it.
    public init(
        intentAPI: any IntentAPI,
        surface: RuntimeSurface = .recipe
    ) {
        self.intentAPI = intentAPI
        self.surface = surface
    }

    public func execute(
        intent: ActionIntent,
        plannerDecision: PlannerDecision,
        selectedCandidate: ElementCandidate?
    ) -> ToolResult {
        executeViaIntentAPI(
            intentAPI,
            intent: intent,
            plannerDecision: plannerDecision,
            selectedCandidate: selectedCandidate
        )
    }

    // MARK: - IntentAPI translation path

    /// Translates ActionIntent to the typed Intent model and submits via IntentAPI.
    /// This is the approved path — no direct executor calls.
    private func executeViaIntentAPI(
        _ api: any IntentAPI,
        intent: ActionIntent,
        plannerDecision: PlannerDecision,
        selectedCandidate: ElementCandidate?
    ) -> ToolResult {
        let domain: IntentDomain = intent.agentKind == .code ? .code :
            (intent.agentKind == .mixed ? .system : .ui)

        var metadata = [
            "query": intent.query ?? intent.text ?? intent.name,
            "source": "runtime-execution-driver.\(surface.rawValue)",
            "surface": surface.rawValue,
            "plannerSource": plannerDecision.source.rawValue,
            "plannerFamily": plannerDecision.plannerFamily.rawValue,
        ]
        if let selectedCandidate {
            metadata["selectedElementID"] = selectedCandidate.element.id
            metadata["selectedElementLabel"] = selectedCandidate.element.label
        }
        if let encodedIntent = Self.encodeActionIntent(intent) {
            metadata["action_intent_base64"] = encodedIntent
        }

        let typedIntent = Intent(
            domain: domain,
            objective: intent.name,
            metadata: metadata
        )

        // Submit intent via API — the sole approved execution gateway
        let submissionState = SubmissionState(
            result: ToolResult(success: false, error: "IntentAPI submission pending")
        )
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) { [submissionState, semaphore] in
            do {
                let response = try await api.submitIntent(typedIntent)
                submissionState.result = Self.makeToolResult(from: response)
            } catch {
                submissionState.result = ToolResult(
                    success: false,
                    data: [
                        "summary": "Intent submission failed",
                        "method": "intent-api",
                        "action_result": [
                            "success": false,
                            "verified": false,
                            "executed_through_executor": false,
                            "failure_class": "intent_submission_failed",
                            "message": error.localizedDescription,
                        ] as [String: Any],
                    ],
                    error: error.localizedDescription
                )
            }
            semaphore.signal()
        }

        let timedOut: Bool = {
            if Thread.isMainThread {
                // Keep the main run loop pumping while we synchronously wait so
                // MainActor-bound executor work can complete without deadlocking.
                let deadline = Date().addingTimeInterval(Self.submissionTimeoutSeconds)
                while Date() < deadline {
                    if semaphore.wait(timeout: .now()) == .success {
                        return false
                    }
                    _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
                }
                return true
            }
            return semaphore.wait(timeout: .now() + Self.submissionTimeoutSeconds) == .timedOut
        }()

        if timedOut {
            return ToolResult(
                success: false,
                data: [
                    "summary": "Intent submission timed out",
                    "method": "intent-api",
                    "action_result": [
                        "success": false,
                        "verified": false,
                        "executed_through_executor": false,
                        "failure_class": "intent_submission_timeout",
                        "message": "Intent submission timed out after \(Int(Self.submissionTimeoutSeconds))s",
                    ] as [String: Any],
                ],
                error: "Intent submission timed out after \(Int(Self.submissionTimeoutSeconds))s"
            )
        }

        return submissionState.result
    }

    nonisolated private static func makeToolResult(from response: IntentResponse) -> ToolResult {
        let success = response.outcome == .success || response.outcome == .skipped
        let isPlanningFailure = response.summary.lowercased().hasPrefix("planning failed")

        var actionResult: [String: Any] = [
            "success": success,
            "verified": success,
            "executed_through_executor": !isPlanningFailure,
            "message": response.summary,
            "method": "intent-api",
        ]
        if response.outcome == .partialSuccess {
            actionResult["failure_class"] = "partial_success"
        } else if response.outcome == .failed {
            actionResult["failure_class"] = isPlanningFailure ? "planning_failed" : "runtime_failed"
        }

        var data: [String: Any] = [
            "summary": response.summary,
            "cycleID": response.cycleID.uuidString,
            "method": "intent-api",
            "action_result": actionResult,
            "trace": [
                "cycle_id": response.cycleID.uuidString,
                "intent_id": response.intentID.uuidString,
            ] as [String: Any],
        ]
        if let snapshotID = response.snapshotID {
            data["snapshot_id"] = snapshotID.uuidString
        }

        return ToolResult(
            success: success,
            data: data,
            error: response.outcome == .failed ? response.summary : nil
        )
    }

    private static func encodeActionIntent(_ intent: ActionIntent) -> String? {
        guard let data = try? JSONEncoder().encode(intent) else {
            return nil
        }
        return data.base64EncodedString()
    }
}
