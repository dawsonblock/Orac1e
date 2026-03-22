import Foundation
public struct ActionCompleted: Sendable, Codable {
    public static let eventType = "ActionCompleted"
    public let commandID: CommandID; public let status: ExecutionStatus; public let timestamp: Date
    public init(commandID: CommandID, status: ExecutionStatus, timestamp: Date = Date()) {
        self.commandID = commandID; self.status = status; self.timestamp = timestamp }
}
