import Foundation

public struct CompressedTracePattern: Sendable, Equatable {
    public let stateFingerprint: String
    public let actionName: String
    public let resultSuccess: Bool
    public let occurrences: Int
    public let averageElapsedMs: Double

    public init(
        stateFingerprint: String,
        actionName: String,
        resultSuccess: Bool,
        occurrences: Int,
        averageElapsedMs: Double
    ) {
        self.stateFingerprint = stateFingerprint
        self.actionName = actionName
        self.resultSuccess = resultSuccess
        self.occurrences = occurrences
        self.averageElapsedMs = averageElapsedMs
    }
}

public struct TraceAccumulator: Sendable {
    public var count: Int = 0
    public var totalElapsedMs: Double = 0
    public var success: Bool = false

    public init() {}

    public mutating func add(event: TraceEvent) {
        count += 1
        totalElapsedMs += event.elapsedMs
        if event.success {
            success = true
        }
    }

    public var averageElapsedMs: Double {
        count > 0 ? totalElapsedMs / Double(count) : 0
    }
}

public enum TraceVerbosity: Sendable {
    case minimal
    case full
}

public struct TraceCompressor: Sendable {

    public init() {}

    public func compress(events: [TraceEvent]) -> [CompressedTracePattern] {
        var grouped: [String: TraceAccumulator] = [:]
        for event in events {
            let key = patternKey(for: event)
            grouped[key, default: TraceAccumulator()].add(event: event)
        }

        return grouped.map { key, acc in
            let parts = key.split(separator: "|", maxSplits: 1)
            return CompressedTracePattern(
                stateFingerprint: parts.count > 0 ? String(parts[0]) : "unknown",
                actionName: parts.count > 1 ? String(parts[1]) : "unknown",
                resultSuccess: acc.success,
                occurrences: acc.count,
                averageElapsedMs: acc.averageElapsedMs
            )
        }
        .sorted { lhs, rhs in
            if lhs.occurrences == rhs.occurrences {
                return lhs.actionName < rhs.actionName
            }
            return lhs.occurrences > rhs.occurrences
        }
    }

    public func successRate(for patterns: [CompressedTracePattern]) -> Double {
        let total = patterns.reduce(0) { $0 + $1.occurrences }
        guard total > 0 else { return 0 }
        let successes = patterns.filter(\.resultSuccess).reduce(0) { $0 + $1.occurrences }
        return Double(successes) / Double(total)
    }

    private func patternKey(for event: TraceEvent) -> String {
        let stateFingerprint = [
            event.planningStateID ?? "no-state",
            event.agentKind ?? "unknown",
            event.domain ?? "no-domain",
        ].joined(separator: ":")
        return "\(stateFingerprint)|\(event.actionName)"
    }

    /// Strips bulky raw data from observations when minimal verbosity is requested.
    ///
    /// The full UI element tree (AX or DOM context) is often thousands of lines JSON
    /// and dominates trace size. In `minimal` mode, we keep only the structurally
    /// significant shell of the observation.
    public func filter(observation: Observation, verbosity: TraceVerbosity) -> Observation {
        switch verbosity {
        case .full:
            return observation
        case .minimal:
            // Strip the full element array but keep the focused element if any,
            // as it often carries localized debug context.
            let retainedElements = observation.focusedElement.map { [$0] } ?? []
            return Observation(
                app: observation.app,
                windowTitle: observation.windowTitle,
                url: observation.url,
                focusedElementID: observation.focusedElementID,
                elements: retainedElements
            )
        }
    }
}
