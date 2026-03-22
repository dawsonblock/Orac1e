import Foundation

public enum PatchStrategyKind: String, CaseIterable, Sendable {
    case boundaryFix = "boundary_fix"
    case nullGuard = "null_guard"
    case typeCorrection = "type_correction"
    case dependencyUpdate = "dependency_update"
    case testExpectationUpdate = "test_expectation_update"
    case configurationFix = "configuration_fix"
}

public struct PatchStrategy: Sendable, Equatable {
    public let kind: PatchStrategyKind
    public let description: String
    public let applicabilitySignals: [String]
    public let baseCost: Double
    public let risk: Double

    public init(
        kind: PatchStrategyKind,
        description: String,
        applicabilitySignals: [String] = [],
        baseCost: Double = 1.0,
        risk: Double = 0.1
    ) {
        self.kind = kind
        self.description = description
        self.applicabilitySignals = applicabilitySignals
        self.baseCost = baseCost
        self.risk = risk
    }
}
