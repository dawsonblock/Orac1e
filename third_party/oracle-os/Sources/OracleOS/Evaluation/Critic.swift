import Foundation
public protocol Critic: Sendable {
    func critique(outcome: ExecutionOutcome) async throws -> CriticReport
}
public struct CriticReport: Sendable, Codable {
    public let outcomeID: UUID; public let score: Double; public let feedback: String; public let timestamp: Date
    public init(outcomeID: UUID, score: Double, feedback: String, timestamp: Date = Date()) {
        self.outcomeID = outcomeID; self.score = score; self.feedback = feedback; self.timestamp = timestamp
    }
}
