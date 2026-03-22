import Foundation
public struct CommandIssued: Sendable, Codable {
    public static let eventType = "CommandIssued"
    public let commandID: CommandID; public let commandKind: String; public let intentID: UUID; public let timestamp: Date
    public init(commandID: CommandID, commandKind: String, intentID: UUID, timestamp: Date = Date()) {
        self.commandID = commandID; self.commandKind = commandKind; self.intentID = intentID; self.timestamp = timestamp }
}
