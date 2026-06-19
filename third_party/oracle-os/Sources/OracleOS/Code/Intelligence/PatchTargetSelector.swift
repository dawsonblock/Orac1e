import Foundation

public struct PatchTarget: Sendable, Equatable {
    public let path: String
    public let score: Double
    public let rootCauseCandidate: RootCauseCandidate
    public let impact: ChangeImpact
    public let blastRadiusPenalty: Double
    public let reasons: [String]

    public init(
        path: String,
        score: Double,
        rootCauseCandidate: RootCauseCandidate,
        impact: ChangeImpact,
        blastRadiusPenalty: Double,
        reasons: [String]
    ) {
        self.path = path
        self.score = score
        self.rootCauseCandidate = rootCauseCandidate
        self.impact = impact
        self.blastRadiusPenalty = blastRadiusPenalty
        self.reasons = reasons
    }
}

public struct PatchTargetSelector: Sendable {
    private let faultRanker: FaultCandidateRanker
    private let impactAnalyzer: RepositoryChangeImpactAnalyzer
    public let blastRadiusThreshold: Double

    public init(
        faultRanker: FaultCandidateRanker = FaultCandidateRanker(),
        impactAnalyzer: RepositoryChangeImpactAnalyzer = RepositoryChangeImpactAnalyzer(),
        blastRadiusThreshold: Double = 0.7
    ) {
        self.faultRanker = faultRanker
        self.impactAnalyzer = impactAnalyzer
        self.blastRadiusThreshold = blastRadiusThreshold
    }

    public func select(
        failureDescription: String,
        in snapshot: RepositorySnapshot,
        preferredPaths: Set<String> = [],
        avoidedPaths: Set<String> = []
    ) -> [PatchTarget] {
        let candidates = faultRanker.rank(
            failureDescription: failureDescription,
            in: snapshot,
            preferredPaths: preferredPaths,
            avoidedPaths: avoidedPaths
        )
        return candidates.map { candidate in
            let impact = impactAnalyzer.impact(of: candidate.path, in: snapshot)
            let blastPenalty = impact.blastRadiusScore > blastRadiusThreshold ? 0.3 : impact.blastRadiusScore * 0.15
            var reasons = candidate.reasons
            if blastPenalty > 0.2 {
                reasons.append("broad patch surface penalized for blast radius \(String(format: "%.2f", impact.blastRadiusScore))")
            }
            return PatchTarget(
                path: candidate.path,
                score: max(0, candidate.score - blastPenalty),
                rootCauseCandidate: candidate,
                impact: impact,
                blastRadiusPenalty: blastPenalty,
                reasons: reasons
            )
        }
        .sorted { $0.score > $1.score }
    }
}
