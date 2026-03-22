// MARK: - RuntimeSnapshot
// Oracle-OS vNext — Read-only view of committed world state for the controller layer.

import Foundation

/// A read-only value type that the controller layer can observe.
/// This is the ONLY state representation the controller may hold.
public struct RuntimeSnapshot: Sendable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let cycleCount: Int
    public let lastIntentID: UUID?
    public let lastCommandKind: String?
    public let status: RuntimeStatus
    public let summary: String

    public enum RuntimeStatus: String, Sendable, Codable {
        case idle
        case planning
        case executing
        case committing
        case evaluating
        case recovering
        case error
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        cycleCount: Int = 0,
        lastIntentID: UUID? = nil,
        lastCommandKind: String? = nil,
        status: RuntimeStatus = .idle,
        summary: String = ""
    ) {
        self.id = id
        self.timestamp = timestamp
        self.cycleCount = cycleCount
        self.lastIntentID = lastIntentID
        self.lastCommandKind = lastCommandKind
        self.status = status
        self.summary = summary
    }
}
