import Foundation

public struct MemoryInfluence: Sendable, Equatable {
    public let executionRankingBias: Double
    public let commandBias: Double
    public let preferredFixPath: String?
    public let preferredRecoveryStrategy: String?
    public let projectMemorySignals: ProjectMemoryPlanningSignals
    public let preferredPaths: [String]
    public let avoidedPaths: [String]
    public let shouldPreferExperiments: Bool
    public let riskPenalty: Double
    public let notes: [String]
    public let evidence: [MemoryEvidence]

    public init(
        executionRankingBias: Double = 0,
        commandBias: Double = 0,
        preferredFixPath: String? = nil,
        preferredRecoveryStrategy: String? = nil,
        projectMemorySignals: ProjectMemoryPlanningSignals = ProjectMemoryPlanningSignals(),
        preferredPaths: [String] = [],
        avoidedPaths: [String] = [],
        shouldPreferExperiments: Bool = false,
        riskPenalty: Double = 0,
        notes: [String] = [],
        evidence: [MemoryEvidence] = []
    ) {
        self.executionRankingBias = executionRankingBias
        self.commandBias = commandBias
        self.preferredFixPath = preferredFixPath
        self.preferredRecoveryStrategy = preferredRecoveryStrategy
        self.projectMemorySignals = projectMemorySignals
        self.preferredPaths = preferredPaths
        self.avoidedPaths = avoidedPaths
        self.shouldPreferExperiments = shouldPreferExperiments
        self.riskPenalty = riskPenalty
        self.notes = notes
        self.evidence = evidence
    }

    public var projectMemoryRefs: [ProjectMemoryRef] {
        projectMemorySignals.refs
    }

    public static let empty = MemoryInfluence()
}
