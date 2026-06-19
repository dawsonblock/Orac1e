import Foundation
public struct ActionFailed: Sendable, Codable {
    public static let eventType = "ActionFailed"
    public let commandID: CommandID; public let reason: String; public let timestamp: Date
    public init(commandID: CommandID, reason: String, timestamp: Date = Date()) {
        self.commandID = commandID; self.reason = reason; self.timestamp = timestamp }
}
