import Foundation

public struct PromptDiagnostics: Codable, Sendable, Equatable {
    public let templateKind: PromptTemplateKind
    public let cacheKey: String
    public let cacheHit: Bool
    public let renderedLength: Int
    public let estimatedTokenCount: Int
    public let contextItemCount: Int
    public let stateItemCount: Int
    public let constraintCount: Int
    public let actionCount: Int
    public let knowledgeItemCount: Int
    public let expectedOutputCount: Int
    public let evaluationCriteriaCount: Int
    public let warnings: [String]
    public let preview: String

    public init(
        templateKind: PromptTemplateKind,
        cacheKey: String,
        cacheHit: Bool,
        renderedLength: Int,
        estimatedTokenCount: Int,
        contextItemCount: Int,
        stateItemCount: Int,
        constraintCount: Int,
        actionCount: Int,
        knowledgeItemCount: Int,
        expectedOutputCount: Int,
        evaluationCriteriaCount: Int,
        warnings: [String],
        preview: String
    ) {
        self.templateKind = templateKind
        self.cacheKey = cacheKey
        self.cacheHit = cacheHit
        self.renderedLength = renderedLength
        self.estimatedTokenCount = estimatedTokenCount
        self.contextItemCount = contextItemCount
        self.stateItemCount = stateItemCount
        self.constraintCount = constraintCount
        self.actionCount = actionCount
        self.knowledgeItemCount = knowledgeItemCount
        self.expectedOutputCount = expectedOutputCount
        self.evaluationCriteriaCount = evaluationCriteriaCount
        self.warnings = warnings
        self.preview = preview
    }

    public static func build(
        document: PromptDocument,
        cacheKey: String,
        cacheHit: Bool,
        validation: PromptValidationResult
    ) -> PromptDiagnostics {
        let preview = document.rendered.count <= 240
            ? document.rendered
            : String(document.rendered.prefix(239)) + "…"

        return PromptDiagnostics(
            templateKind: document.templateKind,
            cacheKey: cacheKey,
            cacheHit: cacheHit,
            renderedLength: document.rendered.count,
            estimatedTokenCount: validation.estimatedTokenCount,
            contextItemCount: document.context.context.count,
            stateItemCount: document.context.state.count,
            constraintCount: document.context.constraints.count,
            actionCount: document.context.availableActions.count,
            knowledgeItemCount: document.context.relevantKnowledge.count,
            expectedOutputCount: document.context.expectedOutput.count,
            evaluationCriteriaCount: document.context.evaluationCriteria.count,
            warnings: validation.warnings + [validation.hardFailure].compactMap { $0 },
            preview: preview
        )
    }
}
