import Foundation

public struct ExperimentDecision: Codable, Sendable, Equatable {
    public let reason: String
    public let candidateCount: Int
    public let architectureRiskScore: Double

    public init(reason: String, candidateCount: Int, architectureRiskScore: Double) {
        self.reason = reason
        self.candidateCount = candidateCount
        self.architectureRiskScore = architectureRiskScore
    }
}
