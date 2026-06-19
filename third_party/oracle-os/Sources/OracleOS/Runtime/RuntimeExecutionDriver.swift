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
                submissionState.result = Self.makeSubmissionFailureResult(
                    summary: "Intent submission failed",
                    errorMessage: error.localizedDescription,
                    failureClass: "intent_submission_failed"
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
            let message = "Intent submission timed out after \(Int(Self.submissionTimeoutSeconds))s"
            return Self.makeSubmissionFailureResult(
                summary: "Intent submission timed out",
                errorMessage: message,
                failureClass: "intent_submission_timeout"
            )
        }

        return submissionState.result
    }

    nonisolated private static func makeToolResult(from response: IntentResponse) -> ToolResult {
        let success = response.outcome == .success || response.outcome == .skipped
        let isPlanningFailure = response.summary.lowercased().hasPrefix("planning failed")

        let actionResult = ActionResult(
            success: success,
            verified: success,
            message: response.summary,
            method: "intent-api",
            failureClass: response.outcome == .partialSuccess
                ? "partial_success"
                : (response.outcome == .failed ? (isPlanningFailure ? "planning_failed" : "runtime_failed") : nil),
            executedThroughExecutor: !isPlanningFailure
        )
        let trace = TraceResult(
            cycleID: response.cycleID.uuidString,
            intentID: response.intentID.uuidString,
            snapshotID: response.snapshotID?.uuidString
        )
        let payload = RuntimeBoundaryResult(
            summary: response.summary,
            method: "intent-api",
            actionResult: actionResult,
            trace: trace
        )

        return MCPBoundary.makeToolResult(
            success: success,
            payload: payload,
            error: response.outcome == .failed ? response.summary : nil
        )
    }

    nonisolated private static func makeSubmissionFailureResult(
        summary: String,
        errorMessage: String,
        failureClass: String
    ) -> ToolResult {
        let payload = RuntimeBoundaryResult(
            summary: summary,
            method: "intent-api",
            actionResult: ActionResult(
                success: false,
                verified: false,
                message: errorMessage,
                method: "intent-api",
                failureClass: failureClass,
                executedThroughExecutor: false
            )
        )
        return MCPBoundary.makeToolResult(success: false, payload: payload, error: errorMessage)
    }

    private static func encodeActionIntent(_ intent: ActionIntent) -> String? {
        guard let data = try? JSONEncoder().encode(intent) else {
            return nil
        }
        return data.base64EncodedString()
    }
}
