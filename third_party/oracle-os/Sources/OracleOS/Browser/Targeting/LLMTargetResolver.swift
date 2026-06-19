import Foundation

public struct LLMTargetCandidate: Sendable {
    public let elementDescription: String
    public let confidence: Double
    public let rationale: String

    public init(
        elementDescription: String,
        confidence: Double,
        rationale: String = ""
    ) {
        self.elementDescription = elementDescription
        self.confidence = confidence
        self.rationale = rationale
    }
}

public struct LLMTargetResolution: Sendable {
    public let candidates: [LLMTargetCandidate]
    public let llmUsed: Bool
    public let notes: [String]

    public init(
        candidates: [LLMTargetCandidate],
        llmUsed: Bool = false,
        notes: [String] = []
    ) {
        self.candidates = candidates
        self.llmUsed = llmUsed
        self.notes = notes
    }
}

public final class LLMTargetResolver: @unchecked Sendable {
    private let llmClient: LLMClient
    private let minimumConfidence: Double

    public init(
        llmClient: LLMClient,
        minimumConfidence: Double = 0.6
    ) {
        self.llmClient = llmClient
        self.minimumConfidence = minimumConfidence
    }

    public func resolve(
        goal: String,
        domSummary: String,
        visibleElements: [String],
        selectedStrategy: SelectedStrategy
    ) async -> LLMTargetResolution {
        let prompt = buildBrowserPrompt(
            goal: goal,
            domSummary: domSummary,
            visibleElements: visibleElements,
            selectedStrategy: selectedStrategy
        )
        let request = LLMRequest(
            prompt: prompt,
            modelTier: .browserReasoning,
            maxTokens: 512
        )

        do {
            let response = try await llmClient.complete(request)
            let candidates = parseCandidates(from: response.text, visibleElements: visibleElements)
            return LLMTargetResolution(
                candidates: candidates.filter { $0.confidence >= minimumConfidence },
                llmUsed: true,
                notes: ["LLM browser reasoning completed"]
            )
        } catch {
            return LLMTargetResolution(
                candidates: [],
                llmUsed: false,
                notes: ["LLM unavailable for browser target resolution"]
            )
        }
    }

    private func buildBrowserPrompt(
        goal: String,
        domSummary: String,
        visibleElements: [String],
        selectedStrategy: SelectedStrategy
    ) -> String {
        var lines: [String] = []

        // ── Strategy context ──
        lines.append("Current strategy: \(selectedStrategy.kind.rawValue)")
        lines.append("Allowed operator families: \(selectedStrategy.allowedOperatorFamilies.map(\.rawValue).joined(separator: ", "))")
        lines.append("")

        lines.append("User goal:")
        lines.append(goal)
        lines.append("")
        lines.append("Page summary:")
        lines.append(domSummary)
        lines.append("")
        lines.append("Visible elements:")
        for element in visibleElements.prefix(20) {
            lines.append("- \(element)")
        }
        lines.append("")
        lines.append("Choose the correct element to interact with and explain why.")
        lines.append("Format each candidate as:")
        lines.append("element: <description>")
        lines.append("confidence: <0.0 to 1.0>")
        lines.append("reason: <explanation>")
        return lines.joined(separator: "\n")
    }

    private func parseCandidates(from text: String, visibleElements: [String]) -> [LLMTargetCandidate] {
        var candidates: [LLMTargetCandidate] = []
        var currentElement = ""
        var currentConfidence = 0.5
        var currentReason = ""

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lowered = trimmed.lowercased()

            if lowered.hasPrefix("element:") {
                if !currentElement.isEmpty {
                    candidates.append(LLMTargetCandidate(
                        elementDescription: currentElement,
                        confidence: currentConfidence,
                        rationale: currentReason
                    ))
                }
                currentElement = trimmed.dropFirst("element:".count)
                    .trimmingCharacters(in: .whitespaces)
                currentConfidence = 0.5
                currentReason = ""
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

        if !currentElement.isEmpty {
            candidates.append(LLMTargetCandidate(
                elementDescription: currentElement,
                confidence: currentConfidence,
                rationale: currentReason
            ))
        }

        // Normalize and filter candidates to the provided visible elements.
        let normalizedVisibleElements: [String] = visibleElements.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func bestMatchingVisibleElement(for description: String) -> String? {
            let normalizedDescription = description
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            guard !normalizedDescription.isEmpty else {
                return nil
            }

            var bestMatch: String?
            var bestScore = 0

            for element in normalizedVisibleElements {
                let normalizedElement = element.lowercased()

                var score = 0
                if normalizedElement == normalizedDescription {
                    // Strongest match: exact (case-insensitive).
                    score = 3
                } else if normalizedElement.contains(normalizedDescription) || normalizedDescription.contains(normalizedElement) {
                    // Next best: one string contains the other.
                    score = 2
                } else {
                    // Weak match: any shared word between the two strings.
                    let descriptionWords = Set(normalizedDescription.split(separator: " "))
                    let elementWords = Set(normalizedElement.split(separator: " "))
                    if !descriptionWords.isDisjoint(with: elementWords) {
                        score = 1
                    }
                }

                if score > bestScore {
                    bestScore = score
                    bestMatch = element
                }
            }

            // Require at least some non-trivial similarity.
            return bestScore > 0 ? bestMatch : nil
        }

        let filteredCandidates: [LLMTargetCandidate] = candidates.compactMap { candidate in
            guard let matchedElement = bestMatchingVisibleElement(for: candidate.elementDescription) else {
                // Drop candidates that cannot be mapped to any visible element.
                return nil
            }

            // Normalize elementDescription to the matched visible element.
            return LLMTargetCandidate(
                elementDescription: matchedElement,
                confidence: candidate.confidence,
                rationale: candidate.rationale
            )
        }

        return filteredCandidates.sorted { $0.confidence > $1.confidence }
    }
}
