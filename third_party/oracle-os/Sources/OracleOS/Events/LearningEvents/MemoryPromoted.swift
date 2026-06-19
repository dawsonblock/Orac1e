import Foundation
public struct MemoryPromoted: Sendable, Codable {
    public static let eventType = "MemoryPromoted"
    public let candidateID: UUID; public let memoryClass: String; public let timestamp: Date
    public init(candidateID: UUID, memoryClass: String, timestamp: Date = Date()) {
        self.candidateID = candidateID; self.memoryClass = memoryClass; self.timestamp = timestamp }
}
