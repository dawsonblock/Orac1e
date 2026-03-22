import Foundation

/// Records an action's lifecycle derived from EventEnvelope history.
/// Traces must derive from event history — not scattered manual logs.
public struct ActionTrace: Sendable, Codable {
    public let commandID: CommandID
    public let intentID: UUID
    public let startTime: Date
    public let endTime: Date?
    public let domain: String
    public let outcome: String?
    public let eventCount: Int

    public init(
        commandID: CommandID,
        intentID: UUID,
        startTime: Date,
        endTime: Date? = nil,
        domain: String,
        outcome: String? = nil,
        eventCount: Int = 0
    ) {
        self.commandID = commandID
        self.intentID = intentID
        self.startTime = startTime
        self.endTime = endTime
        self.domain = domain
        self.outcome = outcome
        self.eventCount = eventCount
    }

    /// Factory: build an ActionTrace from a sequence of EventEnvelopes for the same command.
    public static func from(events: [EventEnvelope], domain: String) -> ActionTrace? {
        guard let commandID = events.first?.commandID,
              let intentID = events.first?.intentID else { return nil }
        let startTime = events.map(\.timestamp).min() ?? Date()
        let endTime = events.map(\.timestamp).max()
        let completedEvent = events.first { $0.eventType == "actionCompleted" }
        let failedEvent = events.first { $0.eventType == "actionFailed" }
        let outcome = completedEvent != nil ? "completed" : (failedEvent != nil ? "failed" : "unknown")
        return ActionTrace(
            commandID: commandID,
            intentID: intentID,
            startTime: startTime,
            endTime: endTime,
            domain: domain,
            outcome: outcome,
            eventCount: events.count
        )
    }

    public var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }
}
