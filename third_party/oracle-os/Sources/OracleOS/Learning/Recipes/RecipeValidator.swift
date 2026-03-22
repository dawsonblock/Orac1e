import Foundation

public enum RecipeValidator {

    // MARK: - Validation Result

    /// Structured result of recipe validation.
    public struct ValidationResult: Sendable {
        public let isValid: Bool
        public let violations: [String]

        public init(isValid: Bool, violations: [String] = []) {
            self.isValid = isValid
            self.violations = violations
        }
    }

    // MARK: - Full Validation

    /// Validates recipe structure including postconditions and constraints.
    /// Returns a `ValidationResult` with detailed violation messages.
    public static func validateFull(
        recipe: Recipe,
        state _: WorldState
    ) -> ValidationResult {
        var violations: [String] = []

        // Steps must exist.
        guard !recipe.steps.isEmpty else {
            return ValidationResult(isValid: false, violations: ["Recipe has no steps"])
        }

        let declaredParameters = Set(recipe.params?.map(\.key) ?? [])

        for step in recipe.steps {
            // Action must be non-empty.
            if step.action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                violations.append("Step \(step.id) has empty action")
            }
            // Referenced parameters must be declared.
            let referencedParameters = referencedParameters(in: step)
            let undeclared = referencedParameters.subtracting(declaredParameters)
            if !undeclared.isEmpty {
                violations.append("Step \(step.id) references undeclared params: \(undeclared.sorted().joined(separator: ", "))")
            }
            // Wait timeouts must be non-negative.
            if let timeout = step.waitAfter?.timeout, timeout < 0 {
                violations.append("Step \(step.id) has negative wait timeout: \(timeout)")
            }
        }

        // Postcondition validation.
        let validPostconditionKinds: Set<String> = [
            "element_exists", "element_focused", "element_value_equals",
            "element_appeared", "element_disappeared",
            "file_exists", "window_visible", "app_frontmost", "url_contains",
        ]
        if let postconditions = recipe.postconditions {
            for pc in postconditions {
                if pc.kind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    violations.append("Postcondition has empty kind")
                }
                if pc.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    violations.append("Postcondition '\(pc.kind)' has empty target")
                }
                if !validPostconditionKinds.contains(pc.kind) {
                    violations.append("Postcondition '\(pc.kind)' is not a recognised kind")
                }
            }
        }

        // Constraint validation.
        if let constraints = recipe.constraints {
            if let maxDuration = constraints.maxDurationSeconds, maxDuration <= 0 {
                violations.append("Constraint max_duration_seconds must be positive, got \(maxDuration)")
            }
            if let maxRetries = constraints.maxRetries, maxRetries < 0 {
                violations.append("Constraint max_retries must be non-negative, got \(maxRetries)")
            }
        }

        return ValidationResult(isValid: violations.isEmpty, violations: violations)
    }

    // MARK: - Legacy Bool API

    public static func validate(
        recipe: Recipe,
        state: WorldState
    ) -> Bool {
        return validateFull(recipe: recipe, state: state).isValid
    }

    public static func validateWorkflow(
        _ plan: WorkflowPlan,
        against segments: [TraceSegment],
        replayValidator: WorkflowReplayValidator = WorkflowReplayValidator(),
        promotionPolicy: WorkflowPromotionPolicy = WorkflowPromotionPolicy(),
        decayPolicy: WorkflowDecayPolicy = WorkflowDecayPolicy()
    ) -> Bool {
        guard !plan.steps.isEmpty else {
            return false
        }
        guard decayPolicy.isStale(plan) == false else {
            return false
        }

        let replayScore = replayValidator.validate(plan: plan, against: segments)
        let candidate = WorkflowPlan(
            id: plan.id,
            agentKind: plan.agentKind,
            goalPattern: plan.goalPattern,
            steps: plan.steps,
            parameterSlots: plan.parameterSlots,
            parameterKinds: plan.parameterKinds,
            parameterExamples: plan.parameterExamples,
            successRate: plan.successRate,
            sourceTraceRefs: plan.sourceTraceRefs,
            sourceGraphEdgeRefs: plan.sourceGraphEdgeRefs,
            evidenceTiers: plan.evidenceTiers,
            repeatedTraceSegmentCount: plan.repeatedTraceSegmentCount,
            replayValidationSuccess: replayScore,
            promotionStatus: plan.promotionStatus,
            lastValidatedAt: plan.lastValidatedAt,
            lastSucceededAt: plan.lastSucceededAt
        )
        return promotionPolicy.shouldPromote(candidate)
    }

    private static func referencedParameters(in step: RecipeStep) -> Set<String> {
        let texts = (step.params.map { Array($0.values) } ?? [])
            + [step.waitAfter?.value, step.note].compactMap { $0 }
        let regex = try? NSRegularExpression(pattern: #"\{\{\s*([a-zA-Z0-9_\-]+)\s*\}\}"#)
        var references = Set<String>()

        for text in texts {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            regex?.enumerateMatches(in: text, options: [], range: nsRange) { match, _, _ in
                guard let match,
                      match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: text)
                else {
                    return
                }
                references.insert(String(text[range]))
            }
        }

        return references
    }
}
