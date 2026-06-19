import Foundation
import OracleControllerShared
import OracleOS

private final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) {
        lock.lock()
        buffer.append(data)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        let data = buffer
        lock.unlock()
        return data
    }

    func reset() {
        lock.lock()
        buffer = Data()
        lock.unlock()
    }
}

enum ClaudeLocalCopilot {
    static let providerID = "claude-local"

    static func status() -> ChatProviderStatus {
        let command = locateCLIPath()
        let configured = isOracleMCPConfigured()

        guard let command else {
            return ChatProviderStatus(
                providerID: providerID,
                displayName: "Claude Local",
                state: .setupRequired,
                configured: false,
                available: false,
                canStream: false,
                detail: "Install the Claude CLI and run `oracle setup` to enable copilot responses."
            )
        }

        guard configured else {
            return ChatProviderStatus(
                providerID: providerID,
                displayName: "Claude Local",
                state: .setupRequired,
                configured: false,
                available: true,
                canStream: true,
                command: command,
                detail: "Claude CLI is installed, but Oracle OS is not configured in ~/.claude.json. Run `oracle setup`."
            )
        }

        return ChatProviderStatus(
            providerID: providerID,
            displayName: "Claude Local",
            state: .ready,
            configured: true,
            available: true,
            canStream: true,
            command: command,
            detail: "Claude CLI is installed and Oracle OS is configured for local advisory responses."
        )
    }

    static func setupGuidance(for status: ChatProviderStatus) -> String {
        switch status.state {
        case .ready:
            return "Claude Local is ready."
        case .setupRequired:
            return """
            Claude Local is not ready yet.

            1. Install the Claude CLI.
            2. Run `oracle setup` so Oracle OS is registered in `~/.claude.json`.
            3. Reopen Oracle Controller and try the copilot again.
            """
        case .unavailable:
            return "Claude Local is currently unavailable. Verify the CLI and configuration, then retry."
        }
    }

    static func complete(
        conversation: ChatConversation,
        prompt: String,
        missionControl: MissionControlSnapshot,
        onDelta: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        let status = status()
        guard status.available, status.configured, let command = status.command else {
            return setupGuidance(for: status)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.currentDirectoryURL = OracleProductPaths.developerProjectRoot

        var arguments = [
            "-p",
            buildPrompt(prompt: prompt, conversation: conversation, missionControl: missionControl),
            "--append-system-prompt",
            systemPrompt(),
            "--output-format",
            "text",
            "--tools",
            "",
        ]

        if let cwd = OracleProductPaths.developerProjectRoot?.path {
            arguments.append(contentsOf: ["--cwd", cwd])
        }

        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let accumulated = LockedDataBuffer()

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            accumulated.append(data)

            if let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty {
                Task {
                    await onDelta(chunk)
                }
            }
        }

        try process.run()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { task in
                    stdout.fileHandleForReading.readabilityHandler = nil

                    let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                    let outputData = accumulated.snapshot()

                    let text = String(data: outputData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        ?? ""

                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }

                    if task.terminationStatus == 0, !text.isEmpty {
                        continuation.resume(returning: text)
                        return
                    }

                    let errorText = String(data: errorData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    accumulated.reset()

                    let message = errorText?.isEmpty == false
                        ? errorText!
                        : "Claude CLI exited with status \(task.terminationStatus)."
                    continuation.resume(throwing: CopilotError.executionFailed(message))
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }

    static func citations(for prompt: String, missionControl: MissionControlSnapshot) -> [ChatCitation] {
        let query = prompt.lowercased()
        var citations: [ChatCitation] = []

        if query.contains("approval") || !missionControl.approvals.isEmpty {
            citations.append(contentsOf: missionControl.approvals.prefix(2).map {
                ChatCitation(
                    id: "approval-\($0.id)",
                    title: $0.displayTitle,
                    summary: $0.reason,
                    kind: .approval,
                    targetID: $0.id,
                    targetSectionID: "missionControl"
                )
            })
        }

        if let alert = missionControl.alerts.first {
            citations.append(
                ChatCitation(
                    id: "alert-\(alert.id)",
                    title: alert.title,
                    summary: alert.message,
                    kind: .health,
                    targetID: alert.id,
                    targetSectionID: "health"
                )
            )
        }

        if let trace = missionControl.traceSessions.first {
            citations.append(
                ChatCitation(
                    id: "trace-\(trace.id)",
                    title: "Trace \(trace.id)",
                    summary: "\(trace.stepCount) steps recorded",
                    kind: .trace,
                    targetID: trace.id,
                    targetSectionID: "traces"
                )
            )
        }

        if let repo = missionControl.repositoryIndexes.first {
            citations.append(
                ChatCitation(
                    id: "repo-\(repo.id)",
                    title: repo.workspaceRoot,
                    summary: "\(repo.fileCount) files indexed on \(repo.activeBranch ?? "current branch")",
                    kind: .diagnostics,
                    targetID: repo.id,
                    targetSectionID: "diagnostics"
                )
            )
        }

        return Array(citations.prefix(4))
    }

    static func drafts(for missionControl: MissionControlSnapshot) -> [ChatActionDraft] {
        var drafts: [ChatActionDraft] = []

        if let appName = missionControl.snapshot?.observation.appName, !appName.isEmpty {
            drafts.append(
                ChatActionDraft(
                    id: "focus-\(appName)",
                    title: "Focus \(appName)",
                    subtitle: "Route a safe focus action through the verified executor.",
                    kind: .action,
                    actionRequest: ActionRequest(kind: .focus, appName: appName)
                )
            )
        }

        if missionControl.health.permissions.contains(where: { !$0.granted }) {
            drafts.append(
                ChatActionDraft(
                    id: "open-health",
                    title: "Open Health",
                    subtitle: "Inspect permissions and setup issues.",
                    kind: .openSection,
                    sectionID: "health"
                )
            )
        }

        if !missionControl.approvals.isEmpty {
            drafts.append(
                ChatActionDraft(
                    id: "open-mission-control",
                    title: "Review approvals",
                    subtitle: "Jump back to Mission Control and inspect the approval queue.",
                    kind: .openSection,
                    sectionID: "missionControl"
                )
            )
        }

        return Array(drafts.prefix(3))
    }

    private static func buildPrompt(
        prompt: String,
        conversation: ChatConversation,
        missionControl: MissionControlSnapshot
    ) -> String {
        let recentMessages = conversation.messages.suffix(6).map {
            "\($0.role.rawValue.uppercased()): \($0.content)"
        }.joined(separator: "\n\n")

        let kpis = missionControl.kpis.map { "\($0.title): \($0.value) (\($0.detail))" }.joined(separator: "\n")
        let alerts = missionControl.alerts.prefix(4).map { "\($0.severity.rawValue.uppercased()): \($0.title) - \($0.message)" }.joined(separator: "\n")
        let approvals = missionControl.approvals.prefix(4).map { "\($0.displayTitle) [\($0.riskLevel)]" }.joined(separator: "\n")
        let workflows = missionControl.workflows.prefix(3).map { "\($0.goalPattern) (\(Int($0.successRate * 100))%)" }.joined(separator: "\n")
        let experiments = missionControl.experiments.prefix(2).map { "\($0.id): \(String(describing: $0.selectedCandidateID ?? "no winner"))" }.joined(separator: "\n")

        return """
        User request:
        \(prompt)

        Mission Control summary:
        \(kpis)

        Alerts:
        \(alerts.isEmpty ? "None" : alerts)

        Pending approvals:
        \(approvals.isEmpty ? "None" : approvals)

        Workflow signals:
        \(workflows.isEmpty ? "None" : workflows)

        Experiment signals:
        \(experiments.isEmpty ? "None" : experiments)

        Recent conversation:
        \(recentMessages.isEmpty ? "No prior messages." : recentMessages)
        """
    }

    private static func systemPrompt() -> String {
        """
        You are the Oracle Controller copilot inside a supervised local macOS operator console.
        Keep answers concise, operational, and advisory-only.
        Do not claim to have taken actions.
        Do not suggest bypassing approvals, policy, or verified execution.
        Prefer the current mission-control state, traces, diagnostics, approvals, and health data.
        """
    }

    private static func locateCLIPath() -> String? {
        let fileManager = FileManager.default
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude",
        ] + path.split(separator: ":").map { "\($0)/claude" }

        return candidates.first(where: { fileManager.isExecutableFile(atPath: $0) })
    }

    private static func isOracleMCPConfigured() -> Bool {
        guard let data = FileManager.default.contents(atPath: NSHomeDirectory() + "/.claude.json"),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mcpServers = object["mcpServers"] as? [String: Any]
        else {
            return false
        }

        return mcpServers["oracle-os"] != nil
    }
}

enum CopilotError: LocalizedError {
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .executionFailed(let message):
            return message
        }
    }
}
