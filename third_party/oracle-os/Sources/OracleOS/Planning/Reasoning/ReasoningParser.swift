import Foundation

public struct ParsedPlan: Sendable {
    public let steps: [ReasoningOperatorKind]
    public let confidence: Double
    public let risk: String
    public let rationale: String

    public init(
        steps: [ReasoningOperatorKind],
        confidence: Double,
        risk: String = "low",
        rationale: String = ""
    ) {
        self.steps = steps
        self.confidence = confidence
        self.risk = risk
        self.rationale = rationale
    }
}

public enum ReasoningParser {
    public static func parsePlans(from text: String) -> [ParsedPlan] {
        let planBlocks = extractPlanBlocks(from: text)
        return planBlocks.compactMap { parseSinglePlan($0) }
    }

    public static func toPlanCandidates(
        parsedPlans: [ParsedPlan],
        state: ReasoningPlanningState,
        operatorRegistry: OperatorRegistry = .shared
    ) -> [PlanCandidate] {
        parsedPlans.compactMap { parsed in
            let operators = parsed.steps.compactMap { kind -> Operator? in
                guard let op = operatorRegistry.makeOperator(kind: kind, state: state) else {
                    return nil
                }
                return op.precondition(state) ? op : nil
            }
            guard !operators.isEmpty else { return nil }

            var projected = state
            for op in operators {
                projected = op.effect(projected)
            }

            let riskScore: Double
            switch parsed.risk.lowercased() {
            case "high":
                riskScore = 0.7
            case "medium":
                riskScore = 0.4
            default:
                riskScore = 0.15
            }

            return PlanCandidate(
                operators: operators,
                projectedState: projected,
                score: parsed.confidence,
                reasons: parsed.rationale.isEmpty ? [] : [parsed.rationale],
                riskScore: riskScore,
                successProbability: parsed.confidence
            )
        }
    }

    private static func extractPlanBlocks(from text: String) -> [String] {
        var blocks: [String] = []
        var current: [String] = []
        var inPlan = false

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.uppercased().hasPrefix("PLAN ") && trimmed.contains(where: \.isNumber) {
                if inPlan && !current.isEmpty {
                    blocks.append(current.joined(separator: "\n"))
                }
                current = []
                inPlan = true
                continue
            }
            if inPlan {
                current.append(trimmed)
            }
        }
        if inPlan && !current.isEmpty {
            blocks.append(current.joined(separator: "\n"))
        }
        return blocks
    }

    private static func parseSinglePlan(_ block: String) -> ParsedPlan? {
        var steps: [ReasoningOperatorKind] = []
        var confidence = 0.5
        var risk = "low"
        var rationale = ""

        for line in block.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lowered = trimmed.lowercased()

            if lowered.hasPrefix("- ") {
                let stepText = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if let kind = matchOperatorKind(stepText) {
                    steps.append(kind)
                }
            } else if lowered.hasPrefix("confidence:") {
                let value = trimmed.dropFirst("confidence:".count).trimmingCharacters(in: .whitespaces)
                confidence = Double(value) ?? 0.5
            } else if lowered.hasPrefix("risk:") {
                risk = trimmed.dropFirst("risk:".count).trimmingCharacters(in: .whitespaces)
            } else if lowered.hasPrefix("rationale:") || lowered.hasPrefix("reason:") {
                let separator = lowered.hasPrefix("rationale:") ? "rationale:" : "reason:"
                rationale = trimmed.dropFirst(separator.count).trimmingCharacters(in: .whitespaces)
            }
        }

        guard !steps.isEmpty else { return nil }
        return ParsedPlan(steps: steps, confidence: confidence, risk: risk, rationale: rationale)
    }

    private static func matchOperatorKind(_ text: String) -> ReasoningOperatorKind? {
        let lowered = text.lowercased()
        let mapping: [(String, ReasoningOperatorKind)] = [
            ("run tests", .runTests),
            ("run_tests", .runTests),
            ("rerun tests", .rerunTests),
            ("rerun_tests", .rerunTests),
            ("build", .buildProject),
            ("build_project", .buildProject),
            ("apply patch", .applyPatch),
            ("apply_patch", .applyPatch),
            ("edit file", .applyPatch),
            ("generate patch", .applyPatch),
            ("revert patch", .revertPatch),
            ("revert_patch", .revertPatch),
            ("dismiss modal", .dismissModal),
            ("dismiss_modal", .dismissModal),
            ("click", .clickTarget),
            ("click_target", .clickTarget),
            ("open app", .openApplication),
            ("open_application", .openApplication),
            ("open application", .openApplication),
            ("navigate", .navigateBrowser),
            ("navigate_browser", .navigateBrowser),
            ("focus window", .focusWindow),
            ("focus_window", .focusWindow),
            ("restart app", .restartApplication),
            ("restart_application", .restartApplication),
            ("rollback", .rollbackPatch),
            ("rollback_patch", .rollbackPatch),
            ("retry", .retryWithAlternateTarget),
            ("retry_alternate_target", .retryWithAlternateTarget),
            ("open repo", .openApplication),
        ]

        for (pattern, kind) in mapping {
            if lowered.contains(pattern) {
                return kind
            }
        }
        return nil
    }
}

public extension OperatorRegistry {
    /// Create an `Operator` for the given kind and planning state using this registry.
    /// The default implementation simply constructs `Operator(kind:)`, preserving
    /// existing behavior while allowing custom registries to override this method.
    func makeOperator(
        kind: ReasoningOperatorKind,
        state: ReasoningPlanningState
    ) -> Operator? {
        Operator(kind: kind)
    }
}
