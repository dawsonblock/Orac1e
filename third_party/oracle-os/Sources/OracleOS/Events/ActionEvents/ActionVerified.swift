import Foundation
public struct ActionVerified: Sendable, Codable {
    public static let eventType = "ActionVerified"
    public let commandID: CommandID; public let passed: Bool; public let notes: String; public let timestamp: Date
    public init(commandID: CommandID, passed: Bool, notes: String = "", timestamp: Date = Date()) {
        self.commandID = commandID; self.passed = passed; self.notes = notes; self.timestamp = timestamp }
}
