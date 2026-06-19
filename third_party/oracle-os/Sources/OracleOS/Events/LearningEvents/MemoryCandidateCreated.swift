import Foundation
public struct MemoryCandidateCreated: Sendable, Codable {
    public static let eventType = "MemoryCandidateCreated"
    public let candidateID: UUID; public let source: String; public let timestamp: Date
    public init(candidateID: UUID = UUID(), source: String, timestamp: Date = Date()) {
        self.candidateID = candidateID; self.source = source; self.timestamp = timestamp }
}
