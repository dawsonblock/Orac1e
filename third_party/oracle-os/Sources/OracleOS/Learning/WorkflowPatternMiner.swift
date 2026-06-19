import Foundation

public struct WorkflowPattern: Sendable {
    public let fingerprint: String
    public let segments: [TraceSegment]
    public let planningStateConsistency: Double
    public let parameterConsistency: Double
    public let reusable: Bool
    public let notes: [String]

    public init(
        fingerprint: String,
        segments: [TraceSegment],
        planningStateConsistency: Double,
        parameterConsistency: Double,
        reusable: Bool,
        notes: [String] = []
    ) {
        self.fingerprint = fingerprint
        self.segments = segments
        self.planningStateConsistency = planningStateConsistency
        self.parameterConsistency = parameterConsistency
        self.reusable = reusable
        self.notes = notes
    }
}

public struct WorkflowPatternMiner: Sendable {
    public let minimumPlanningStateConsistency: Double
    public let minimumParameterConsistency: Double

    public init(
        minimumPlanningStateConsistency: Double = 0.6,
        minimumParameterConsistency: Double = 0.5
    ) {
        self.minimumPlanningStateConsistency = minimumPlanningStateConsistency
        self.minimumParameterConsistency = minimumParameterConsistency
    }

    public func mine(events: [TraceEvent]) -> [WorkflowPattern] {
        let standardPatterns = TraceSegmenter.repeatedSegments(events: events)
            .map { pattern(for: $0) }
            .filter(\.reusable)
        let recoveryPatterns = TraceSegmenter.repeatedRecoverySegments(events: events)
            .map { pattern(for: $0) }
            .filter(\.reusable)
        let combinedPatterns = standardPatterns + recoveryPatterns

        var seenFingerprints = Set<String>()
        let uniquePatterns = combinedPatterns.filter { pattern in
            if seenFingerprints.contains(pattern.fingerprint) {
                return false
            }
            seenFingerprints.insert(pattern.fingerprint)
            return true
        }

        return uniquePatterns
            .sorted { lhs, rhs in
                if lhs.planningStateConsistency == rhs.planningStateConsistency {
                    if lhs.parameterConsistency == rhs.parameterConsistency {
                        return lhs.fingerprint < rhs.fingerprint
                    }
                    return lhs.parameterConsistency > rhs.parameterConsistency
                }
                return lhs.planningStateConsistency > rhs.planningStateConsistency
            }
    }

    private func pattern(for group: RepeatedTraceSegment) -> WorkflowPattern {
        let parameters = ParameterExtractor.extract(from: group.segments)
        let planningStateConsistency = planningStateConsistency(for: group.segments)
        let parameterConsistency = parameterConsistency(parameters: parameters, segments: group.segments)
        let residueNotes = residueNotes(for: group.segments, parameters: parameters)

        var notes: [String] = [
            "planning state consistency \(String(format: "%.2f", planningStateConsistency))",
            "parameter consistency \(String(format: "%.2f", parameterConsistency))",
        ]
        notes.append(contentsOf: residueNotes)

        let reusable =
            planningStateConsistency >= minimumPlanningStateConsistency
            && parameterConsistency >= minimumParameterConsistency
            && residueNotes.isEmpty

        return WorkflowPattern(
            fingerprint: group.fingerprint,
            segments: group.segments,
            planningStateConsistency: planningStateConsistency,
            parameterConsistency: parameterConsistency,
            reusable: reusable,
            notes: notes
        )
    }

    private func planningStateConsistency(for segments: [TraceSegment]) -> Double {
        guard let stepCount = segments.map({ $0.events.count }).min(), stepCount > 0 else {
            return 0
        }

        let perStepScores: [Double] = (0..<stepCount).map { stepIndex in
            let stateIDs = segments.compactMap { segment -> String? in
                guard segment.events.indices.contains(stepIndex) else { return nil }
                return segment.events[stepIndex].planningStateID
            }
            guard !stateIDs.isEmpty else { return 0 }
            let grouped = Dictionary(grouping: stateIDs, by: { $0 })
            let dominant = grouped.values.map(\.count).max() ?? 0
            return Double(dominant) / Double(stateIDs.count)
        }

        return perStepScores.reduce(0, +) / Double(perStepScores.count)
    }

    private func parameterConsistency(
        parameters: [ExtractedParameter],
        segments: [TraceSegment]
    ) -> Double {
        guard !segments.isEmpty else { return 0 }
        guard !parameters.isEmpty else { return 1 }

        let consistentCount = parameters.filter { parameter in
            let values = Set(parameter.values.filter { !$0.isEmpty })
            switch parameter.kind {
            case "url", "file-path", "branch", "test-name", "repository", "ui-label":
                return values.count == segments.count || values.count > 1
            default:
                return values.isEmpty == false
            }
        }.count

        return Double(consistentCount) / Double(parameters.count)
    }

    private func residueNotes(
        for segments: [TraceSegment],
        parameters: [ExtractedParameter]
    ) -> [String] {
        let examples = parameters.flatMap(\.values)
        let parameterizedResidue = examples.filter { value in
            value.contains("/tmp/")
                || value.contains("/private/var/")
                || value.contains("/var/folders/")
                || value.contains("/.oracle/experiments/")
                || value.contains("sandbox-")
                || value.contains("candidate-")
                || value.range(of: #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#, options: .regularExpression) != nil
        }
        if parameterizedResidue.isEmpty == false {
            return ["parameter examples contain episode-specific residue"]
        }

        let varyingSandboxText = segments.contains { segment in
            let values = Set(
                segment.events.compactMap(\.sandboxPath)
                    + segment.events.compactMap(\.workspaceRelativePath)
            )
            return values.contains { value in
                value.contains("/.oracle/experiments/")
                    || value.contains("/tmp/")
                    || value.contains("sandbox-")
            }
        }

        if varyingSandboxText {
            return ["trace segments contain sandbox-specific residue"]
        }

        return []
    }
}
