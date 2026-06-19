import Foundation

public struct ElementCandidate: Sendable {

    public let element: UnifiedElement
    public let score: Double
    public let reasons: [String]
    public let ambiguityScore: Double

    public init(
        element: UnifiedElement,
        score: Double,
        reasons: [String],
        ambiguityScore: Double = 0
    ) {
        self.element = element
        self.score = score
        self.reasons = reasons
        self.ambiguityScore = ambiguityScore
    }
}
