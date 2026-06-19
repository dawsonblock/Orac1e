import Foundation
public struct ExecutionTrace: Sendable, Codable {
    public let commandID: CommandID; public let preconditionsPassed: Bool; public let postconditionsPassed: Bool
    public let status: ExecutionStatus; public let timestamp: Date
    public init(commandID: CommandID, preconditionsPassed: Bool, postconditionsPassed: Bool, status: ExecutionStatus, timestamp: Date = Date()) {
        self.commandID = commandID; self.preconditionsPassed = preconditionsPassed
        self.postconditionsPassed = postconditionsPassed; self.status = status; self.timestamp = timestamp }
}
