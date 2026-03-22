import Foundation

public struct LLMRecoveryPlan: Sendable {
    public let strategies: [LLMRecoveryStrategy]
    public let llmUsed: Bool
    public let notes: [String]

    public init(
        strategies: [LLMRecoveryStrategy],
        llmUsed: Bool = false,
        notes: [String] = []
    ) {
        self.strategies = strategies
        self.llmUsed = llmUsed
        self.notes = notes
    }
}

public struct LLMRecoveryStrategy: Sendable {
    public let name: String
    public let layer: RecoveryLayer = .replan
    public let description: String
    public let confidence: Double
    public let rationale: String

    public init(
        name: String,
        description: String,
        confidence: Double,
        rationale: String = ""
    ) {
        self.name = name
        self.description = description
        self.confidence = confidence
        self.rationale = rationale
    }
}

public final class LLMRecoveryAdvisor: @unchecked Sendable {
    private let llmClient: LLMClient

    public init(llmClient: LLMClient) {
        self.llmClient = llmClient
    }

    public func advise(
        failureClass: FailureClass,
        recentActions: [String],
        memoryInfluence: MemoryInfluence,
        selectedStrategy: SelectedStrategy? = nil
    ) async -> LLMRecoveryPlan {
        let prompt = buildRecoveryPrompt(
            failureClass: failureClass,
            recentActions: recentActions,
            memoryInfluence: memoryInfluence,
            selectedStrategy: selectedStrategy
        )
        let request = LLMRequest(
            prompt: prompt,
            modelTier: .recovery,
            maxTokens: 512
        )

        do {
            let response = try await llmClient.complete(request)
            let strategies = parseRecoveryStrategies(from: response.text)
            return LLMRecoveryPlan(
                strategies: strategies,
                llmUsed: true,
                notes: ["LLM recovery reasoning completed"]
            )
        } catch {
            return LLMRecoveryPlan(
                strategies: defaultStrategies(
                    failureClass: failureClass,
                    memoryInfluence: memoryInfluence
                ),
                llmUsed: false,
                notes: ["LLM unavailable, using deterministic recovery fallback"]
            )
        }
    }

    private func buildRecoveryPrompt(
        failureClass: FailureClass,
        recentActions: [String],
        memoryInfluence: MemoryInfluence,
        selectedStrategy: SelectedStrategy? = nil
    ) -> String {
        var lines: [String] = []

        // ── Strategy context ──
        if let strategy = selectedStrategy {
            lines.append("Current strategy: \(strategy.kind.rawValue)")
            lines.append("Allowed operator families: \(strategy.allowedOperatorFamilies.map(\.rawValue).joined(separator: ", "))")
            lines.append("IMPORTANT: Only suggest recovery strategies using allowed operators.")
            lines.append("")
        }

        lines.append("Automation failed.")
        lines.append("")
        lines.append("Failure type: \(failureClass.rawValue)")
        lines.append("")
        lines.append("Recent actions:")
        for action in recentActions.suffix(10) {
            lines.append("- \(action)")
        }
        if let preferred = memoryInfluence.preferredRecoveryStrategy {
            lines.append("")
            lines.append("Previously successful recovery: \(preferred)")
        }
        lines.append("")
        lines.append("Suggest recovery strategies ordered by confidence.")
        lines.append("Format each as:")
        lines.append("strategy: <name>")
        lines.append("description: <what to do>")
        lines.append("confidence: <0.0 to 1.0>")
        lines.append("reason: <why this should work>")
        return lines.joined(separator: "\n")
    }

    private func parseRecoveryStrategies(from text: String) -> [LLMRecoveryStrategy] {
        var strategies: [LLMRecoveryStrategy] = []
        var currentName = ""
        var currentDescription = ""
        var currentConfidence = 0.5
        var currentReason = ""

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lowered = trimmed.lowercased()

            if lowered.hasPrefix("strategy:") {
                if !currentName.isEmpty {
                    strategies.append(LLMRecoveryStrategy(
                        name: currentName,
                        description: currentDescription,
                        confidence: currentConfidence,
                        rationale: currentReason
                    ))
                }
                currentName = trimmed.dropFirst("strategy:".count)
                    .trimmingCharacters(in: .whitespaces)
                currentDescription = ""
                currentConfidence = 0.5
                currentReason = ""
            } else if lowered.hasPrefix("description:") {
                currentDescription = trimmed.dropFirst("description:".count)
                    .trimmingCharacters(in: .whitespaces)
            } else if lowered.hasPrefix("confidence:") {
                let value = trimmed.dropFirst("confidence:".count)
                    .trimmingCharacters(in: .whitespaces)
                currentConfidence = Double(value) ?? 0.5
            } else if lowered.hasPrefix("reason:") || lowered.hasPrefix("rationale:") {
                let prefix = lowered.hasPrefix("reason:") ? "reason:" : "rationale:"
                currentReason = trimmed.dropFirst(prefix.count)
                    .trimmingCharacters(in: .whitespaces)
            }
        }

        if !currentName.isEmpty {
            strategies.append(LLMRecoveryStrategy(
                name: currentName,
                description: currentDescription,
                confidence: currentConfidence,
                rationale: currentReason
            ))
        }

        return strategies.sorted { $0.confidence > $1.confidence }
    }

    private func defaultStrategies(
        failureClass: FailureClass,
        memoryInfluence: MemoryInfluence
    ) -> [LLMRecoveryStrategy] {
        var strategies: [LLMRecoveryStrategy] = []

        if let preferred = memoryInfluence.preferredRecoveryStrategy {
            strategies.append(LLMRecoveryStrategy(
                name: preferred,
                description: "Use previously successful recovery strategy from memory",
                confidence: 0.7,
                rationale: "Memory indicates prior success with this strategy"
            ))
        }

        switch failureClass {
        case .modalBlocking, .unexpectedDialog:
            strategies.append(LLMRecoveryStrategy(
                name: "dismiss_modal",
                description: "Dismiss the blocking modal or dialog",
                confidence: 0.8,
                rationale: "Modal is blocking the current action"
            ))
        case .elementNotFound, .elementAmbiguous, .targetMissing:
            strategies.append(LLMRecoveryStrategy(
                name: "refresh_observation",
                description: "Refresh the observation and retry target resolution",
                confidence: 0.65,
                rationale: "Element state may have changed"
            ))
        case .wrongFocus:
            strategies.append(LLMRecoveryStrategy(
                name: "refocus_application",
                description: "Refocus the target application window",
                confidence: 0.75,
                rationale: "Application focus was lost"
            ))
        case .buildFailed, .testFailed:
            strategies.append(LLMRecoveryStrategy(
                name: "revert_patch",
                description: "Revert the applied patch and retry with a different approach",
                confidence: 0.6,
                rationale: "Current patch may have introduced the failure"
            ))
        default:
            strategies.append(LLMRecoveryStrategy(
                name: "refresh_observation",
                description: "Refresh observation state and retry",
                confidence: 0.5,
                rationale: "General recovery by refreshing state"
            ))
        }

        return strategies
    }
}
