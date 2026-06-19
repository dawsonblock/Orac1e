import Foundation
public struct PlanCommitted: Sendable, Codable {
    public static let eventType = "PlanCommitted"
    public let intentID: UUID; public let commandKind: String; public let strategy: String; public let timestamp: Date
    public init(intentID: UUID, commandKind: String, strategy: String, timestamp: Date = Date()) {
        self.intentID = intentID; self.commandKind = commandKind; self.strategy = strategy; self.timestamp = timestamp }
}
