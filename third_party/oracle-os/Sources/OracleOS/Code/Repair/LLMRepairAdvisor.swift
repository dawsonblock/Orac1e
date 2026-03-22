import Foundation

public struct RepairStrategy: Sendable {
    public let description: String
    public let targetPath: String?
    public let confidence: Double
    public let predictedEffect: String
    public let risk: String

    public init(
        description: String,
        targetPath: String? = nil,
        confidence: Double,
        predictedEffect: String = "",
        risk: String = "low"
    ) {
        self.description = description
        self.targetPath = targetPath
        self.confidence = confidence
        self.predictedEffect = predictedEffect
        self.risk = risk
    }
}

public struct RepairAdvice: Sendable {
    public let strategies: [RepairStrategy]
    public let diagnostics: RepairAdviceDiagnostics

    public init(
        strategies: [RepairStrategy],
        diagnostics: RepairAdviceDiagnostics = RepairAdviceDiagnostics()
    ) {
        self.strategies = strategies
        self.diagnostics = diagnostics
    }
}

public struct RepairAdviceDiagnostics: Sendable {
    public let llmUsed: Bool
    public let candidateCount: Int
    public let notes: [String]

    public init(
        llmUsed: Bool = false,
        candidateCount: Int = 0,
        notes: [String] = []
    ) {
        self.llmUsed = llmUsed
        self.candidateCount = candidateCount
        self.notes = notes
    }
}

public final class LLMRepairAdvisor: @unchecked Sendable {
    private let llmClient: LLMClient

    public init(llmClient: LLMClient) {
        self.llmClient = llmClient
    }

    public func advise(
        errorSignature: String,
        faultCandidates: [String],
        memoryInfluence: MemoryInfluence,
        selectedStrategy: SelectedStrategy
    ) async -> RepairAdvice {
        let prompt = buildRepairPrompt(
            errorSignature: errorSignature,
            faultCandidates: faultCandidates,
            memoryInfluence: memoryInfluence,
            selectedStrategy: selectedStrategy
        )
        let request = LLMRequest(
            prompt: prompt,
            modelTier: .codeRepair,
            maxTokens: 1024
        )

        do {
            let response = try await llmClient.complete(request)
            let strategies = parseRepairStrategies(from: response.text, faultCandidates: faultCandidates)
            return RepairAdvice(
                strategies: strategies,
                diagnostics: RepairAdviceDiagnostics(
                    llmUsed: true,
                    candidateCount: strategies.count,
                    notes: ["LLM repair reasoning completed"]
                )
            )
        } catch {
            return RepairAdvice(
                strategies: defaultStrategies(faultCandidates: faultCandidates, memoryInfluence: memoryInfluence),
                diagnostics: RepairAdviceDiagnostics(
                    llmUsed: false,
                    candidateCount: faultCandidates.count,
                    notes: ["LLM unavailable, using deterministic fallback"]
                )
            )
        }
    }

    private func buildRepairPrompt(
        errorSignature: String,
        faultCandidates: [String],
        memoryInfluence: MemoryInfluence,
        selectedStrategy: SelectedStrategy
    ) -> String {
        var lines: [String] = []

        // ── Strategy context ──
        lines.append("Current strategy: \(selectedStrategy.kind.rawValue)")
        lines.append("Allowed operator families: \(selectedStrategy.allowedOperatorFamilies.map(\.rawValue).joined(separator: ", "))")
        lines.append("")

        lines.append("A test or build failed.")
        lines.append("")
        lines.append("Error signature:")
        lines.append(errorSignature)
        lines.append("")
        lines.append("Top fault candidates:")
        for path in faultCandidates.prefix(10) {
            lines.append("- \(path)")
        }
        if let preferred = memoryInfluence.preferredFixPath {
            lines.append("")
            lines.append("Memory suggests fixing: \(preferred)")
        }
        if !memoryInfluence.avoidedPaths.isEmpty {
            lines.append("Memory suggests avoiding: \(memoryInfluence.avoidedPaths.joined(separator: ", "))")
        }
        lines.append("")
        lines.append("Suggest up to 3 repair strategies.")
        lines.append("Each strategy should include:")
        lines.append("- description")
        lines.append("- target file path")
        lines.append("- confidence (0.0 to 1.0)")
        lines.append("- predicted effect")
        lines.append("- risk level")
        return lines.joined(separator: "\n")
    }

    private func parseRepairStrategies(from text: String, faultCandidates: [String]) -> [RepairStrategy] {
        var strategies: [RepairStrategy] = []
        var currentDescription = ""
        var currentPath: String?
        var currentConfidence = 0.5
        var currentEffect = ""
        var currentRisk = "low"

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lowered = trimmed.lowercased()

            if lowered.hasPrefix("strategy") && lowered.contains(":") {
                if !currentDescription.isEmpty {
                    strategies.append(RepairStrategy(
                        description: currentDescription,
                        targetPath: currentPath,
                        confidence: currentConfidence,
                        predictedEffect: currentEffect,
                        risk: currentRisk
                    ))
                }
                currentDescription = ""
                currentPath = nil
                currentConfidence = 0.5
                currentEffect = ""
                currentRisk = "low"
            } else if lowered.hasPrefix("description:") || lowered.hasPrefix("- description:") {
                currentDescription = trimmed
                    .replacingOccurrences(of: "- description:", with: "")
                    .replacingOccurrences(of: "description:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if lowered.hasPrefix("target:") || lowered.hasPrefix("- target:") || lowered.hasPrefix("path:") || lowered.hasPrefix("- path:") {
                let value = trimmed
                    .replacingOccurrences(of: "- target:", with: "")
                    .replacingOccurrences(of: "target:", with: "")
                    .replacingOccurrences(of: "- path:", with: "")
                    .replacingOccurrences(of: "path:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                currentPath = value
            } else if lowered.hasPrefix("confidence:") || lowered.hasPrefix("- confidence:") {
                let value = trimmed
                    .replacingOccurrences(of: "- confidence:", with: "")
                    .replacingOccurrences(of: "confidence:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                currentConfidence = Double(value) ?? 0.5
            } else if lowered.hasPrefix("effect:") || lowered.hasPrefix("- effect:") || lowered.hasPrefix("predicted effect:") {
                currentEffect = trimmed
                    .replacingOccurrences(of: "- effect:", with: "")
                    .replacingOccurrences(of: "predicted effect:", with: "")
                    .replacingOccurrences(of: "effect:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if lowered.hasPrefix("risk:") || lowered.hasPrefix("- risk:") {
                currentRisk = trimmed
                    .replacingOccurrences(of: "- risk:", with: "")
                    .replacingOccurrences(of: "risk:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
        }

        if !currentDescription.isEmpty {
            strategies.append(RepairStrategy(
                description: currentDescription,
                targetPath: currentPath,
                confidence: currentConfidence,
                predictedEffect: currentEffect,
                risk: currentRisk
            ))
        }

        return strategies.isEmpty
            ? defaultStrategies(faultCandidates: faultCandidates, memoryInfluence: MemoryInfluence.empty)
            : strategies
    }

    private func defaultStrategies(
        faultCandidates: [String],
        memoryInfluence: MemoryInfluence
    ) -> [RepairStrategy] {
        var strategies: [RepairStrategy] = []

        if let preferred = memoryInfluence.preferredFixPath {
            strategies.append(RepairStrategy(
                description: "Fix preferred path from memory",
                targetPath: preferred,
                confidence: 0.6,
                predictedEffect: "Addresses historically successful repair location",
                risk: "low"
            ))
        }

        for path in faultCandidates.prefix(2) {
            strategies.append(RepairStrategy(
                description: "Inspect and patch fault candidate",
                targetPath: path,
                confidence: 0.4,
                predictedEffect: "May resolve the failure based on fault ranking",
                risk: "medium"
            ))
        }

        return strategies
    }
}
