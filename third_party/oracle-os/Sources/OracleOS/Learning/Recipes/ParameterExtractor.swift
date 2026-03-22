import Foundation

public struct ExtractedParameter: Sendable, Equatable {
    public let name: String
    public let kind: String
    public let values: [String]
    public let stepIndex: Int?

    public init(name: String, kind: String, values: [String], stepIndex: Int? = nil) {
        self.name = name
        self.kind = kind
        self.values = values
        self.stepIndex = stepIndex
    }
}

public enum ParameterExtractor {
    public static func extract(steps: [RecipeStep]) -> ([RecipeStep], [String]) {
        var params: Set<String> = []
        let updatedSteps = steps.map { step -> RecipeStep in
            var stepParams = step.params ?? [:]
            let actionExtraction = extractParameters(from: step.action)
            let noteExtraction = extractParameters(from: step.note)

            for parameter in actionExtraction + noteExtraction {
                params.insert(parameter.name)
                stepParams[parameter.name] = parameter.values.first ?? ""
            }

            let action = applyParameters(to: step.action, parameters: actionExtraction) ?? step.action
            let note = applyParameters(to: step.note, parameters: noteExtraction)

            return RecipeStep(
                id: step.id,
                action: action,
                target: step.target,
                params: stepParams.isEmpty ? nil : stepParams,
                waitAfter: step.waitAfter,
                note: note,
                onFailure: step.onFailure
            )
        }

        return (updatedSteps, Array(params).sorted())
    }

    public static func extract(from segments: [TraceSegment]) -> [ExtractedParameter] {
        guard let minimumStepCount = segments.map({ $0.events.count }).min(),
              minimumStepCount > 0
        else {
            return []
        }

        var parameters: [ExtractedParameter] = []
        for stepIndex in 0..<minimumStepCount {
            let events: [TraceEvent] = segments.compactMap { segment -> TraceEvent? in
                guard segment.events.indices.contains(stepIndex) else { return nil }
                return segment.events[stepIndex]
            }
            parameters.append(contentsOf: groupedParameters(for: events, stepIndex: stepIndex))
        }

        return parameters
    }

    private static func extractParameters(from text: String?) -> [ExtractedParameter] {
        guard let text, !text.isEmpty else { return [] }
        return buildParameters(kind: "url", prefix: "url", values: orderedUnique(matches(in: text, using: #"https?://\S+"#)))
            + buildParameters(kind: "file-path", prefix: "path", values: orderedUnique(matches(in: text, using: #"(?:(?:[A-Za-z0-9_\-]+/)+[A-Za-z0-9_\-\.]+)"#)))
            + buildParameters(kind: "branch", prefix: "branch", values: orderedUnique(matches(in: text, using: #"(?:(?:feature|bugfix|hotfix|release)/[A-Za-z0-9_\-\.]+)"#)))
            + buildParameters(kind: "test-name", prefix: "test", values: orderedUnique(matches(in: text, using: #"(?:test[A-Za-z0-9_]+|[A-Za-z0-9_]+Tests(?:/[A-Za-z0-9_]+)?)"#)))
    }

    private static func applyParameters(to text: String?, parameters: [ExtractedParameter]) -> String? {
        guard var text else { return text }
        for parameter in parameters {
            for value in parameter.values {
                text = text.replacingOccurrences(of: value, with: "{{\(parameter.name)}}")
            }
        }
        return text
    }

    public static func applySlots(
        to text: String?,
        parameters: [ExtractedParameter],
        stepIndex: Int? = nil
    ) -> String? {
        guard var text else { return text }
        let eligibleParameters = parameters.filter { parameter in
            parameter.stepIndex == nil || parameter.stepIndex == stepIndex
        }
        for parameter in eligibleParameters {
            for value in parameter.values where !value.isEmpty {
                text = text.replacingOccurrences(
                    of: value,
                    with: "{{\(parameter.name)}}"
                )
            }
        }
        return text
    }

    static func firstURLCandidate(in text: String) -> String? {
        firstURL(in: text)
    }

    static func firstFilePathCandidate(in text: String) -> String? {
        firstFilePath(in: text)
    }

    static func firstBranchCandidate(in text: String) -> String? {
        firstBranch(in: text)
    }

    static func firstTestNameCandidate(in text: String) -> String? {
        firstTestName(in: text)
    }

    private static func buildParameters(
        kind: String,
        prefix: String,
        values: [String],
        stepIndex: Int? = nil
    ) -> [ExtractedParameter] {
        let filtered = values.filter { !$0.isEmpty }
        guard !filtered.isEmpty else { return [] }
        return [
            ExtractedParameter(
                name: "\(prefix)_\(stepIndex ?? 0)",
                kind: kind,
                values: filtered,
                stepIndex: stepIndex
            )
        ]
    }

    private static func groupedParameters(
        for events: [TraceEvent],
        stepIndex: Int
    ) -> [ExtractedParameter] {
        let urls = orderedUnique(events.compactMap { event in
            [event.actionTarget, event.actionText]
                .compactMap { $0 }
                .compactMap(firstURL(in:))
                .first
        })
        let filePaths = orderedUnique(events.compactMap { event in
            [event.workspaceRelativePath, event.actionTarget, event.actionText]
                .compactMap { $0 }
                .compactMap(firstFilePath(in:))
                .first
        })
        let branches = orderedUnique(events.compactMap { event in
            [event.commandSummary, event.actionText]
                .compactMap { $0 }
                .compactMap(firstBranch(in:))
                .first
        })
        let tests = orderedUnique(events.compactMap { event in
            [event.actionText, event.commandSummary]
                .compactMap { $0 }
                .compactMap(firstTestName(in:))
                .first
        })
        let repositories = orderedUnique(events.compactMap { event in
            [event.sandboxPath, event.workspaceRelativePath]
                .compactMap { $0 }
                .compactMap(firstRepositoryName(in:))
                .first
        })
        let labels = orderedUnique(events.compactMap { event in
            [event.selectedElementLabel, event.actionTarget].compactMap { $0 }.first
        })

        return varyingParameters(kind: "url", prefix: "url", values: urls, stepIndex: stepIndex)
            + varyingParameters(kind: "file-path", prefix: "path", values: filePaths, stepIndex: stepIndex)
            + varyingParameters(kind: "branch", prefix: "branch", values: branches, stepIndex: stepIndex)
            + varyingParameters(kind: "test-name", prefix: "test", values: tests, stepIndex: stepIndex)
            + varyingParameters(kind: "repository", prefix: "repository", values: repositories, stepIndex: stepIndex)
            + varyingParameters(kind: "ui-label", prefix: "label", values: labels, stepIndex: stepIndex)
    }

    private static func varyingParameters(
        kind: String,
        prefix: String,
        values: [String],
        stepIndex: Int
    ) -> [ExtractedParameter] {
        let filtered = values.filter { !$0.isEmpty }
        guard Set(filtered).count > 1 else {
            return []
        }
        return buildParameters(
            kind: kind,
            prefix: prefix,
            values: filtered,
            stepIndex: stepIndex
        )
    }

    private static func uniqueValues(
        in segments: [TraceSegment],
        extractor: (TraceEvent) -> [String]
    ) -> [String] {
        orderedUnique(
            segments.flatMap { segment in
                segment.events.flatMap(extractor)
            }
        )
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { value in
            seen.insert(value).inserted
        }
    }

    private static func matches(in text: String, using pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    private static func firstURL(in text: String) -> String? {
        matches(in: text, using: #"https?://\S+"#).first
    }

    private static func firstFilePath(in text: String) -> String? {
        matches(in: text, using: #"(?:(?:[A-Za-z0-9_\-]+/)+[A-Za-z0-9_\-\.]+)"#).first
    }

    private static func firstBranch(in text: String) -> String? {
        matches(in: text, using: #"(?:(?:feature|bugfix|hotfix|release)/[A-Za-z0-9_\-\.]+)"#).first
    }

    private static func firstTestName(in text: String) -> String? {
        matches(in: text, using: #"(?:test[A-Za-z0-9_]+|[A-Za-z0-9_]+Tests(?:/[A-Za-z0-9_]+)?)"#).first
    }

    private static func firstRepositoryName(in text: String) -> String? {
        let sanitized = text.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !sanitized.isEmpty else { return nil }
        let components = sanitized.split(separator: "/")
        guard let last = components.last else { return nil }
        if last.contains(".") {
            return components.dropLast().last.map(String.init) ?? String(last)
        }
        return String(last)
    }
}
