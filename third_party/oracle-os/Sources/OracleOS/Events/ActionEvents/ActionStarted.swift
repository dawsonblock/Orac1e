import Foundation
public struct ActionStarted: Sendable, Codable {
    public static let eventType = "ActionStarted"
    public let commandID: CommandID; public let commandKind: String; public let timestamp: Date
    public init(commandID: CommandID, commandKind: String, timestamp: Date = Date()) {
        self.commandID = commandID; self.commandKind = commandKind; self.timestamp = timestamp }
}
