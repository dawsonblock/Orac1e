import Foundation

/// Builds a unified, ordered timeline from event history for replay and debugging.
/// Traces derive from event history and execution outcomes — not scattered logs.
public struct TimelineBuilder {
    public init() {}

    /// Build a timeline from an event sequence, sorted by sequence number.
    public func build(from events: [EventEnvelope]) -> Timeline {
        let sorted = events.sorted { $0.sequenceNumber < $1.sequenceNumber }
        let phases = buildPhases(from: sorted)
        return Timeline(events: sorted, phases: phases)
    }

    private func buildPhases(from events: [EventEnvelope]) -> [TimelinePhase] {
        var phases: [TimelinePhase] = []
        var current: TimelinePhaseKind = .planning
        var phaseStart = events.first?.timestamp ?? Date()
        var phaseEvents: [EventEnvelope] = []

        for event in events {
            let kind = TimelinePhaseKind(eventType: event.eventType)
            if kind != current && !phaseEvents.isEmpty {
                phases.append(TimelinePhase(kind: current, startTime: phaseStart,
                                             endTime: event.timestamp, events: phaseEvents))
                phaseEvents = []
                phaseStart = event.timestamp
                current = kind
            }
            phaseEvents.append(event)
        }
        if !phaseEvents.isEmpty {
            phases.append(TimelinePhase(kind: current, startTime: phaseStart,
                                         endTime: phaseEvents.last?.timestamp, events: phaseEvents))
        }
        return phases
    }
}

// MARK: - Timeline

public struct Timeline: Sendable {
    public let events: [EventEnvelope]
    public let phases: [TimelinePhase]

    public init(events: [EventEnvelope], phases: [TimelinePhase] = []) {
        self.events = events
        self.phases = phases
    }

    public var duration: TimeInterval? {
        guard let first = events.first?.timestamp, let last = events.last?.timestamp else { return nil }
        return last.timeIntervalSince(first)
    }
}

// MARK: - TimelinePhase

public struct TimelinePhase: Sendable {
    public let kind: TimelinePhaseKind
    public let startTime: Date
    public let endTime: Date?
    public let events: [EventEnvelope]
}

// MARK: - TimelinePhaseKind

public enum TimelinePhaseKind: String, Sendable {
    case planning = "planning"
    case execution = "execution"
    case commit = "commit"
    case evaluation = "evaluation"
    case learning = "learning"

    init(eventType: String) {
        switch eventType {
        case "commandIssued", "planCommitted": self = .planning
        case "actionStarted", "actionCompleted", "actionFailed", "actionVerified": self = .execution
        case "artifactProduced": self = .commit
        case "memoryCandidateCreated", "memoryPromoted": self = .learning
        default: self = .execution
        }
    }
}
