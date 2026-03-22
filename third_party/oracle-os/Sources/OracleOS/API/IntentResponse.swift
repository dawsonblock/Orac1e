// MARK: - IntentResponse
// Oracle-OS vNext — Response returned to the controller after an intent cycle completes.

import Foundation

public struct IntentResponse: Sendable, Codable {
    public enum Outcome: String, Sendable, Codable {
        case success
        case failed
        case partialSuccess
        case skipped
    }

    public let intentID: UUID
    public let outcome: Outcome
    public let summary: String
    public let cycleID: UUID
    public let snapshotID: UUID?
    public let timestamp: Date

    public init(
        intentID: UUID,
        outcome: Outcome,
        summary: String,
        cycleID: UUID,
        snapshotID: UUID? = nil,
        timestamp: Date = Date()
    ) {
        self.intentID = intentID
        self.outcome = outcome
        self.summary = summary
        self.cycleID = cycleID
        self.snapshotID = snapshotID
        self.timestamp = timestamp
    }
}
