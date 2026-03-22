import Foundation

public struct QueryOptimizer {
    private let sectionLimits: [PromptTemplateKind: (context: Int, state: Int, constraints: Int, actions: Int, knowledge: Int)]

    public init() {
        sectionLimits = [
            .planning: (8, 8, 6, 8, 8),
            .workflowSelection: (8, 8, 6, 8, 8),
            .codeRepair: (10, 10, 8, 10, 10),
            .experimentGeneration: (10, 8, 8, 10, 10),
            .osAction: (8, 8, 8, 8, 8),
            .recoverySelection: (8, 8, 8, 10, 8),
        ]
    }

    public func optimize(_ context: PromptContext) -> PromptContext {
        let limits = sectionLimits[context.templateKind] ?? (8, 8, 6, 8, 8)
        return PromptContext(
            templateKind: context.templateKind,
            goal: summarizeLine(context.goal, limit: 220),
            context: summarizeSection(context.context, limit: limits.context),
            state: summarizeSection(context.state, limit: limits.state),
            constraints: summarizeSection(context.constraints, limit: limits.constraints),
            availableActions: summarizeSection(context.availableActions, limit: limits.actions),
            relevantKnowledge: summarizeSection(context.relevantKnowledge, limit: limits.knowledge),
            expectedOutput: summarizeSection(context.expectedOutput, limit: 6),
            evaluationCriteria: summarizeSection(context.evaluationCriteria, limit: 6)
        )
    }

    private func summarizeSection(_ lines: [String], limit: Int) -> [String] {
        orderedUnique(lines
            .map { summarizeLine($0, limit: 220) }
            .filter { !$0.isEmpty }
        ).prefix(limit).map(\.self)
    }

    private func summarizeLine(_ line: String, limit: Int) -> String {
        let normalized = line
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else {
            return normalized
        }
        let index = normalized.index(normalized.startIndex, offsetBy: limit - 1)
        return String(normalized[..<index]) + "…"
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
