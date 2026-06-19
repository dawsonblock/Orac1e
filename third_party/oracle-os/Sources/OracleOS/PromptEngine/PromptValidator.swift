import Foundation

public struct PromptValidationResult: Sendable, Equatable {
    public let warnings: [String]
    public let hardFailure: String?
    public let estimatedTokenCount: Int

    public init(
        warnings: [String] = [],
        hardFailure: String? = nil,
        estimatedTokenCount: Int
    ) {
        self.warnings = warnings
        self.hardFailure = hardFailure
        self.estimatedTokenCount = estimatedTokenCount
    }
}

public struct PromptValidator {
    private let maxRenderedCharacters: Int

    public init(maxRenderedCharacters: Int = 8_000) {
        self.maxRenderedCharacters = maxRenderedCharacters
    }

    public func validate(document: PromptDocument) -> PromptValidationResult {
        var warnings: [String] = []
        var hardFailure: String?

        if document.context.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hardFailure = "Prompt goal is empty."
        } else if document.context.state.isEmpty {
            hardFailure = "Prompt state section is empty."
        } else if document.context.expectedOutput.isEmpty {
            hardFailure = "Prompt expected output section is empty."
        } else if document.context.availableActions.isEmpty {
            hardFailure = "Prompt available actions section is empty."
        }

        let estimatedTokenCount = max(1, Int(ceil(Double(document.rendered.count) / 4.0)))

        if document.rendered.count > maxRenderedCharacters {
            warnings.append("Prompt exceeded recommended size and was truncated by optimizer.")
        }
        if document.context.relevantKnowledge.count > 8 {
            warnings.append("Prompt still contains a large knowledge section.")
        }
        if document.context.context.count > 8 {
            warnings.append("Prompt still contains a large context section.")
        }

        return PromptValidationResult(
            warnings: warnings,
            hardFailure: hardFailure,
            estimatedTokenCount: estimatedTokenCount
        )
    }
}
