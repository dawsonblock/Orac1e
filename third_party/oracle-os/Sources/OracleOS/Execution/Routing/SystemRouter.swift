import Foundation

public struct SystemRouter: @unchecked Sendable {
    private let workspaceRunner: WorkspaceRunner?

    init(workspaceRunner: WorkspaceRunner?) {
        self.workspaceRunner = workspaceRunner
    }

    /// Truncate potentially large command output before including it in observations.
    /// - Parameters:
    ///   - text: The original output string.
    ///   - maxLength: Maximum number of characters to retain.
    /// - Returns: The original text if within the limit, otherwise a truncated version with a marker.
    private func truncated(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else {
            return text
        }
        let endIndex = text.index(text.startIndex, offsetBy: maxLength)
        return String(text[..<endIndex]) + "\n... [output truncated]"
    }

    public func execute(
        _ command: Command,
        policyDecision: PolicyDecision
    ) async throws -> RoutedExecutionResult {
        guard command.type == .system else {
            throw RouterError.invalidRoute(expected: .system, actual: command.type)
        }

        switch command.payload {
        case .shell(let spec):
            guard let workspaceRunner else {
                return CommandRouter.failureOutcome(
                    command: command,
                    reason: "Workspace runner unavailable",
                    policyDecision: policyDecision,
                    router: "system"
                )
            }

            let result = try workspaceRunner.execute(spec: spec)
            let observations = [
                ObservationPayload(
                    kind: "system.shell",
                    content: """
                    \(result.summary)
                    stdout:
                    \(truncated(result.stdout, maxLength: 2000))
                    stderr:
                    \(truncated(result.stderr, maxLength: 2000))
                    """
                ),
            ]
            if result.succeeded {
                return CommandRouter.successOutcome(
                    command: command,
                    observations: observations,
                    artifacts: [],
                    policyDecision: policyDecision,
                    router: "system"
                )
            }

            return CommandRouter.failureOutcome(
                command: command,
                reason: result.stderr.isEmpty ? result.stdout : result.stderr,
                policyDecision: policyDecision,
                router: "system"
            )

        case .ui:
            return CommandRouter.failureOutcome(
                command: command,
                reason: "Invalid system payload: received UI action for system command",
                policyDecision: policyDecision,
                router: "system"
            )

        case .code:
            return CommandRouter.failureOutcome(
                command: command,
                reason: "Invalid system payload",
                policyDecision: policyDecision,
                router: "system"
            )
        }
    }
}
