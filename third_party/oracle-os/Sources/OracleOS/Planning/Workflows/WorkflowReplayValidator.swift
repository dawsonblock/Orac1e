import Foundation

public struct WorkflowReplayValidator: Sendable {
    public init() {}

    public func validate(plan: WorkflowPlan, against segments: [TraceSegment]) -> Double {
        guard !segments.isEmpty else { return 0 }

        let matches = segments.filter { segment in
            segmentMatches(plan: plan, segment: segment)
        }

        return Double(matches.count) / Double(segments.count)
    }

    private func segmentMatches(plan: WorkflowPlan, segment: TraceSegment) -> Bool {
        guard segment.events.count == plan.steps.count else {
            return false
        }

        var bindings: [String: String] = [:]
        return zip(plan.steps, segment.events).allSatisfy { step, event in
            guard step.actionContract.skillName == event.actionName else {
                return false
            }
            guard step.agentKind.rawValue == (event.agentKind ?? step.agentKind.rawValue) else {
                return false
            }
            if let fromPlanningStateID = step.fromPlanningStateID,
               fromPlanningStateID != event.planningStateID
            {
                return false
            }
            if step.stepPhase != taskPhase(for: event) {
                return false
            }
            guard matchTemplate(
                expected: step.actionContract.workspaceRelativePath,
                actual: event.workspaceRelativePath,
                parameterKinds: plan.parameterKinds,
                bindings: &bindings
            ) else {
                return false
            }
            guard matchTemplate(
                expected: step.actionContract.targetLabel,
                actual: event.actionTarget ?? event.selectedElementLabel,
                parameterKinds: plan.parameterKinds,
                bindings: &bindings
            ) else {
                return false
            }
            guard matchTemplate(
                expected: step.semanticQuery?.text,
                actual: event.actionTarget ?? event.selectedElementLabel,
                parameterKinds: plan.parameterKinds,
                bindings: &bindings
            ) else {
                return false
            }
            if step.notes.isEmpty {
                return true
            }
            return matchTemplate(
                expected: step.notes.joined(separator: "\n"),
                actual: [event.postconditionClass.map { "postcondition=\($0)" }, event.commandSummary]
                    .compactMap { $0 }
                    .joined(separator: "\n"),
                parameterKinds: plan.parameterKinds,
                bindings: &bindings
            )
        }
    }

    private func taskPhase(for event: TraceEvent) -> TaskStepPhase {
        switch event.plannerFamily {
        case PlannerFamily.code.rawValue:
            return .engineering
        case PlannerFamily.mixed.rawValue:
            return .handoff
        default:
            return .operatingSystem
        }
    }

    private func matchTemplate(
        expected: String?,
        actual: String?,
        parameterKinds: [String: String],
        bindings: inout [String: String]
    ) -> Bool {
        switch (expected, actual) {
        case (nil, _):
            return true
        case let (expected?, actual?):
            let placeholders = placeholderNames(in: expected)
            guard !placeholders.isEmpty else {
                return expected == actual
            }

            var pattern = NSRegularExpression.escapedPattern(for: expected)
            for placeholder in placeholders {
                let token = NSRegularExpression.escapedPattern(for: "{{\(placeholder)}}")
                let kind = parameterKinds[placeholder] ?? kindForSlot(placeholder)
                pattern = pattern.replacingOccurrences(
                    of: token,
                    with: "(.+)"
                )
                _ = kind
            }

            guard let regex = try? NSRegularExpression(pattern: "^\(pattern)$") else {
                return false
            }
            let nsRange = NSRange(actual.startIndex..<actual.endIndex, in: actual)
            guard let match = regex.firstMatch(in: actual, range: nsRange),
                  match.numberOfRanges == placeholders.count + 1
            else {
                return false
            }

            for (index, placeholder) in placeholders.enumerated() {
                let range = match.range(at: index + 1)
                guard let swiftRange = Range(range, in: actual) else {
                    return false
                }
                let captured = String(actual[swiftRange])
                guard slotValueMatchesKind(captured, kind: parameterKinds[placeholder] ?? kindForSlot(placeholder)) else {
                    return false
                }
                if let bound = bindings[placeholder], bound != captured {
                    return false
                }
                bindings[placeholder] = captured
            }
            return true
        case (.some, nil):
            return false
        }
    }

    private func placeholderNames(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\{\{([a-zA-Z0-9_]+)\}\}"#) else {
            return []
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text)
            else {
                return nil
            }
            return String(text[range])
        }
    }

    private func kindForSlot(_ slot: String) -> String {
        if slot.hasPrefix("url_") { return "url" }
        if slot.hasPrefix("path_") { return "file-path" }
        if slot.hasPrefix("branch_") { return "branch" }
        if slot.hasPrefix("test_") { return "test-name" }
        if slot.hasPrefix("repository_") { return "repository" }
        if slot.hasPrefix("label_") { return "ui-label" }
        return "text"
    }

    private func slotValueMatchesKind(_ value: String, kind: String) -> Bool {
        switch kind {
        case "url":
            return ParameterExtractor.firstURLCandidate(in: value) != nil
        case "file-path":
            return ParameterExtractor.firstFilePathCandidate(in: value) != nil
        case "branch":
            return ParameterExtractor.firstBranchCandidate(in: value) != nil
        case "test-name":
            return ParameterExtractor.firstTestNameCandidate(in: value) != nil
        case "repository":
            return value.isEmpty == false && value.contains("/") == false
        case "ui-label":
            return value.isEmpty == false
        default:
            return true
        }
    }
}
