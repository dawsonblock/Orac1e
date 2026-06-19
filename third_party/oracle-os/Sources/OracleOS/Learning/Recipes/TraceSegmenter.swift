import Foundation

public struct TraceSegment: Sendable, Identifiable {
    public let id: String
    public let taskID: String?
    public let sessionID: String
    public let agentKind: AgentKind
    public let events: [TraceEvent]

    public init(
        id: String,
        taskID: String?,
        sessionID: String,
        agentKind: AgentKind,
        events: [TraceEvent]
    ) {
        self.id = id
        self.taskID = taskID
        self.sessionID = sessionID
        self.agentKind = agentKind
        self.events = events
    }

    public var fingerprint: String {
        events.map {
            [
                $0.agentKind ?? "unknown",
                $0.actionName,
                Self.normalizedPlanningStateID($0.planningStateID),
                $0.postconditionClass ?? "none",
                Self.normalizedFingerprintValue($0.actionTarget ?? $0.selectedElementLabel),
                Self.normalizedFingerprintValue($0.workspaceRelativePath),
                $0.commandCategory ?? "none",
            ].joined(separator: "|")
        }
        .joined(separator: "->")
    }

    public var evidenceTiers: [KnowledgeTier] {
        Array(
            Set(
                events.compactMap { $0.knowledgeTier }.compactMap(KnowledgeTier.init(rawValue:))
            )
        ).sorted { $0.rawValue < $1.rawValue }
    }

    public var planningStateDeltas: [String] {
        events.compactMap(\.planningStateID)
    }

    private static func normalizedFingerprintValue(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "none" }
        if ParameterExtractor.firstURLCandidate(in: value) != nil {
            return "{url}"
        }
        if ParameterExtractor.firstFilePathCandidate(in: value) != nil {
            return "{path}"
        }
        if ParameterExtractor.firstBranchCandidate(in: value) != nil {
            return "{branch}"
        }
        if ParameterExtractor.firstTestNameCandidate(in: value) != nil {
            return "{test}"
        }
        return value
    }

    private static func normalizedPlanningStateID(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "none" }
        return value.lowercased()
    }
}

public struct RepeatedTraceSegment: Sendable {
    public let fingerprint: String
    public let segments: [TraceSegment]

    public init(fingerprint: String, segments: [TraceSegment]) {
        self.fingerprint = fingerprint
        self.segments = segments
    }
}

public enum TraceSegmenter {
    public static func segment(events: [TraceEvent]) -> [TraceSegment] {
        segmentFiltered(events: events, includeRecovery: false)
    }

    public static func segmentIncludingRecovery(events: [TraceEvent]) -> [TraceSegment] {
        segmentFiltered(events: events, includeRecovery: true)
    }

    public static func repeatedRecoverySegments(events: [TraceEvent]) -> [RepeatedTraceSegment] {
        let allSegments = segmentIncludingRecovery(events: events)
        // Only include segments that contain at least one recovery-tagged event,
        // so non-recovery segments are not misclassified as recovery patterns.
        let recoveryOnly = allSegments.filter { segment in
            segment.events.contains { event in
                event.recoveryTagged == true
                    || event.knowledgeTier == KnowledgeTier.recovery.rawValue
            }
        }
        let grouped = Dictionary(grouping: recoveryOnly, by: \.fingerprint)
        return grouped
            .compactMap { fingerprint, segments in
                let uniqueEpisodes = Set(
                    segments.map { segment in
                        [segment.sessionID, segment.taskID ?? "none"].joined(separator: "|")
                    }
                )
                guard segments.count >= 2, uniqueEpisodes.count >= 2 else { return nil }
                return RepeatedTraceSegment(fingerprint: fingerprint, segments: segments)
            }
            .sorted { lhs, rhs in
                if lhs.segments.count == rhs.segments.count {
                    return lhs.fingerprint < rhs.fingerprint
                }
                return lhs.segments.count > rhs.segments.count
            }
    }

    private static func segmentFiltered(events: [TraceEvent], includeRecovery: Bool) -> [TraceSegment] {
        var segments: [TraceSegment] = []
        var current: [TraceEvent] = []
        var currentTaskID: String?
        var currentSessionID: String?
        var currentAgentKind: AgentKind?

        func flush() {
            guard let first = current.first,
                  let agentKind = currentAgentKind,
                  !current.isEmpty
            else {
                current = []
                currentTaskID = nil
                currentSessionID = nil
                currentAgentKind = nil
                return
            }

            let id = [
                first.sessionID,
                first.taskID ?? "none",
                "\(first.stepID)",
                "\(current.count)",
            ].joined(separator: "|")
            segments.append(
                TraceSegment(
                    id: id,
                    taskID: currentTaskID,
                    sessionID: currentSessionID ?? first.sessionID,
                    agentKind: agentKind,
                    events: current
                )
            )
            current = []
            currentTaskID = nil
            currentSessionID = nil
            currentAgentKind = nil
        }

        for event in events.sorted(by: traceSortOrder) {
            let isRecoveryEvent = event.recoveryTagged == true
                || event.knowledgeTier == KnowledgeTier.recovery.rawValue
            guard event.success,
                  event.verified,
                  event.blockedByPolicy != true,
                  event.knowledgeTier != KnowledgeTier.experiment.rawValue,
                  (includeRecovery || !isRecoveryEvent),
                  let agentKind = AgentKind(rawValue: event.agentKind ?? AgentKind.os.rawValue)
            else {
                flush()
                continue
            }

            let startsNewSegment =
                current.isEmpty == false && (
                    currentTaskID != event.taskID
                        || currentSessionID != event.sessionID
                        || currentAgentKind != agentKind
                        || (current.last.map { event.stepID <= $0.stepID } ?? false)
                        || browserContextChanged(previous: current.last, current: event)
                        || codePhaseChanged(previous: current.last, current: event)
                )

            if startsNewSegment {
                flush()
            }

            current.append(event)
            currentTaskID = event.taskID
            currentSessionID = event.sessionID
            currentAgentKind = agentKind
        }

        flush()
        return segments.filter { !$0.events.isEmpty }
    }

    public static func repeatedSegments(events: [TraceEvent]) -> [RepeatedTraceSegment] {
        let grouped = Dictionary(grouping: segment(events: events), by: \.fingerprint)
        return grouped
            .compactMap { fingerprint, segments in
                let uniqueEpisodes = Set(
                    segments.map { segment in
                        [segment.sessionID, segment.taskID ?? "none"].joined(separator: "|")
                    }
                )
                guard segments.count >= 2, uniqueEpisodes.count >= 2 else { return nil }
                return RepeatedTraceSegment(fingerprint: fingerprint, segments: segments)
            }
            .sorted { lhs, rhs in
                if lhs.segments.count == rhs.segments.count {
                    return lhs.fingerprint < rhs.fingerprint
                }
                return lhs.segments.count > rhs.segments.count
            }
    }

    private static func traceSortOrder(lhs: TraceEvent, rhs: TraceEvent) -> Bool {
        if lhs.sessionID == rhs.sessionID {
            if lhs.taskID == rhs.taskID {
                return lhs.stepID < rhs.stepID
            }
            return (lhs.taskID ?? "") < (rhs.taskID ?? "")
        }
        return lhs.sessionID < rhs.sessionID
    }

    private static func browserContextChanged(previous: TraceEvent?, current: TraceEvent) -> Bool {
        guard let previous else { return false }
        if let prevDomain = previous.domain, let curDomain = current.domain,
           prevDomain != curDomain {
            return true
        }
        return false
    }

    private static func codePhaseChanged(previous: TraceEvent?, current: TraceEvent) -> Bool {
        guard let previous else { return false }
        if let prevCategory = previous.commandCategory, let curCategory = current.commandCategory,
           prevCategory != curCategory {
            return true
        }
        return false
    }
}
