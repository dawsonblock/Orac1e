import Foundation

public struct PromptDocument: Sendable, Equatable {
    public let templateKind: PromptTemplateKind
    public let context: PromptContext
    public let rendered: String

    public init(
        templateKind: PromptTemplateKind,
        context: PromptContext,
        rendered: String
    ) {
        self.templateKind = templateKind
        self.context = context
        self.rendered = rendered
    }
}

public struct PromptBuilder {
    public init() {}

    public func build(from context: PromptContext) -> PromptDocument {
        let rendered = [
            section("GOAL", [context.goal]),
            section("CONTEXT", context.context),
            section("CURRENT STATE", context.state),
            section("CONSTRAINTS", context.constraints),
            section("AVAILABLE ACTIONS", context.availableActions),
            section("RELEVANT KNOWLEDGE", context.relevantKnowledge),
            section("EXPECTED OUTPUT", context.expectedOutput),
            section("EVALUATION CRITERIA", context.evaluationCriteria),
        ]
        .joined(separator: "\n\n")

        return PromptDocument(
            templateKind: context.templateKind,
            context: context,
            rendered: rendered
        )
    }

    private func section(_ title: String, _ lines: [String]) -> String {
        let body = lines.isEmpty
            ? "- none"
            : lines.map { "- \($0)" }.joined(separator: "\n")
        return "\(title):\n\(body)"
    }
}
