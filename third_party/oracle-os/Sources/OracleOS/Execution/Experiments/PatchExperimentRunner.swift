import Foundation

public struct PatchExperimentResult: Sendable {
    public let candidate: CandidatePatch
    public let strategy: PatchStrategyKind
    public let testsPassed: Bool
    public let buildSucceeded: Bool
    public let coverageImpact: Double
    public let notes: [String]

    public init(
        candidate: CandidatePatch,
        strategy: PatchStrategyKind,
        testsPassed: Bool,
        buildSucceeded: Bool,
        coverageImpact: Double = 0,
        notes: [String] = []
    ) {
        self.candidate = candidate
        self.strategy = strategy
        self.testsPassed = testsPassed
        self.buildSucceeded = buildSucceeded
        self.coverageImpact = coverageImpact
        self.notes = notes
    }

    public var succeeded: Bool {
        testsPassed && buildSucceeded
    }
}

public struct PatchExperimentPlan: Sendable {
    public let errorSignature: String
    public let faultLocationConfidence: Double
    public let candidates: [CandidatePatch]
    public let strategies: [PatchStrategy]

    public init(
        errorSignature: String,
        faultLocationConfidence: Double,
        candidates: [CandidatePatch],
        strategies: [PatchStrategy]
    ) {
        self.errorSignature = errorSignature
        self.faultLocationConfidence = faultLocationConfidence
        self.candidates = candidates
        self.strategies = strategies
    }
}

public final class PatchExperimentRunner: @unchecked Sendable {
    private let experimentManager: ExperimentManager
    private let strategyLibrary: PatchStrategyLibrary

    public init(
        experimentManager: ExperimentManager = ExperimentManager(),
        strategyLibrary: PatchStrategyLibrary = .shared
    ) {
        self.experimentManager = experimentManager
        self.strategyLibrary = strategyLibrary
    }

    public func plan(
        errorSignature: String,
        faultLocationConfidence: Double,
        candidates: [CandidatePatch],
        snapshot: RepositorySnapshot?
    ) -> PatchExperimentPlan {
        let applicableStrategies = strategyLibrary.applicable(
            for: errorSignature,
            snapshot: snapshot
        )
        return PatchExperimentPlan(
            errorSignature: errorSignature,
            faultLocationConfidence: faultLocationConfidence,
            candidates: candidates,
            strategies: applicableStrategies
        )
    }

    public func run(
        spec: ExperimentSpec,
        architectureRiskScore: Double = 0
    ) async throws -> [ExperimentResult] {
        try await experimentManager.run(
            spec: spec,
            architectureRiskScore: architectureRiskScore
        )
    }

    public func rankResults(
        _ results: [ExperimentResult],
        faultLocationConfidence: Double,
memoryStore: UnifiedMemoryStore?
    ) -> [ExperimentResult] {
        let ranker = PatchRanker()
        let ranked = ranker.rank(results)

        return ranked.enumerated().map { index, result in
            ExperimentResult(
                id: result.id,
                experimentID: result.experimentID,
                candidate: result.candidate,
                sandboxPath: result.sandboxPath,
                commandResults: result.commandResults,
                diffSummary: result.diffSummary,
                architectureRiskScore: result.architectureRiskScore,
                architectureFindings: result.architectureFindings,
                refactorProposalID: result.refactorProposalID,
                selected: index == 0,
                promptDiagnostics: result.promptDiagnostics
            )
        }
    }
}
