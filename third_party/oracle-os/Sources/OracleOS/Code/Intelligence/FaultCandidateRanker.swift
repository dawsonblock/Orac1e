import Foundation

public struct FaultCandidateRanker: Sendable {
    private let rootCauseAnalyzer: RootCauseAnalyzer
    public let maximumCandidates: Int

    public init(
        rootCauseAnalyzer: RootCauseAnalyzer = RootCauseAnalyzer(),
        maximumCandidates: Int = 3
    ) {
        self.rootCauseAnalyzer = rootCauseAnalyzer
        self.maximumCandidates = maximumCandidates
    }

    public func rank(
        failureDescription: String,
        in snapshot: RepositorySnapshot,
        preferredPaths: Set<String> = [],
        avoidedPaths: Set<String> = []
    ) -> [RootCauseCandidate] {
        let candidates = rootCauseAnalyzer.analyze(
            failureDescription: failureDescription,
            in: snapshot,
            preferredPaths: preferredPaths,
            avoidedPaths: avoidedPaths
        )
        return constrainToTopCandidates(candidates)
    }

    public func rank(
        failingTest testSymbolID: String,
        in snapshot: RepositorySnapshot,
        preferredPaths: Set<String> = [],
        avoidedPaths: Set<String> = []
    ) -> [RootCauseCandidate] {
        let candidates = rootCauseAnalyzer.analyze(
            failingTest: testSymbolID,
            in: snapshot,
            preferredPaths: preferredPaths,
            avoidedPaths: avoidedPaths
        )
        return constrainToTopCandidates(candidates)
    }

    // Filter out candidates scoring below half the top score to avoid wasting
    // experiment budget on low-confidence locations.
    private func constrainToTopCandidates(_ candidates: [RootCauseCandidate]) -> [RootCauseCandidate] {
        guard candidates.count > maximumCandidates else { return candidates }
        let topCandidates = Array(candidates.prefix(maximumCandidates))
        guard let topScore = topCandidates.first?.score else { return topCandidates }
        let threshold = topScore * 0.5
        return topCandidates.filter { $0.score >= threshold }
    }
}
