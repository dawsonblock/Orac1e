import Foundation

public struct PromptPolicy {
    public init() {}

    public func enforce(on context: PromptContext) -> PromptContext {
        PromptContext(
            templateKind: context.templateKind,
            goal: redact(context.goal),
            context: context.context.map(redact),
            state: context.state.map(redact),
            constraints: orderedUnique(defaultConstraints(for: context.templateKind) + context.constraints.map(redact)),
            availableActions: orderedUnique(context.availableActions.map(redact)),
            relevantKnowledge: context.relevantKnowledge.map(redact),
            expectedOutput: orderedUnique(context.expectedOutput.map(redact)),
            evaluationCriteria: orderedUnique(context.evaluationCriteria.map(redact))
        )
    }

    private func defaultConstraints(for template: PromptTemplateKind) -> [String] {
        var constraints = [
            "Do not bypass runtime policy or verified execution.",
            "Do not assume success without verification.",
        ]

        switch template {
        case .planning, .workflowSelection:
            constraints.append("Prefer trusted workflow or stable graph reuse before exploration.")
        case .codeRepair, .experimentGeneration:
            constraints.append("Keep the patch surface as small as possible.")
            constraints.append("Do not modify tests unless explicitly required.")
        case .osAction:
            constraints.append("Use semantic targeting and fail closed on ambiguity.")
        case .recoverySelection:
            constraints.append("Prefer bounded state-improving recovery before broad retries.")
        }
        return constraints
    }

    private func redact(_ line: String) -> String {
        let patterns = [
            #"sk-[A-Za-z0-9_\-]+"#,
            #"ghp_[A-Za-z0-9]+"#,
            #"Authorization:\s*[A-Za-z0-9\-_\.]+"#,
        ]
        return patterns.reduce(line) { partial, pattern in
            partial.replacingOccurrences(
                of: pattern,
                with: "[REDACTED]",
                options: .regularExpression
            )
        }
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
