import Foundation
public struct DecisionTrace: Sendable, Codable {
    public let intentID: UUID; public let strategy: String; public let confidence: Double; public let timestamp: Date
    public init(intentID: UUID, strategy: String, confidence: Double, timestamp: Date = Date()) {
        self.intentID = intentID; self.strategy = strategy; self.confidence = confidence; self.timestamp = timestamp }
}
