import Foundation

public enum LoopTerminationReason: String, Codable, Sendable {
    case goalAchieved
    case maxSteps
    case policyBlocked
    case approvalTimeout
    case noViablePlan
    case unrecoverableFailure
    case explorationBudgetExceeded
    case lowConfidenceRepeatedFailure
    case loopStalled
}

public struct LoopOutcome: Sendable {
    public let reason: LoopTerminationReason
    public let finalWorldState: WorldState?
    public let steps: Int
    public let recoveries: Int
    public let lastFailure: FailureClass?
    public let diagnostics: LoopDiagnostics

    public init(
        reason: LoopTerminationReason,
        finalWorldState: WorldState?,
        steps: Int,
        recoveries: Int,
        lastFailure: FailureClass? = nil,
        diagnostics: LoopDiagnostics = .empty
    ) {
        self.reason = reason
        self.finalWorldState = finalWorldState
        self.steps = steps
        self.recoveries = recoveries
        self.lastFailure = lastFailure
        self.diagnostics = diagnostics
    }
}
