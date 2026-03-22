import Foundation

public struct RoutedExecutionResult: Sendable {
    public let status: ExecutionStatus
    public let evidence: ExecutionEvidence

    public init(status: ExecutionStatus, evidence: ExecutionEvidence) {
        self.status = status
        self.evidence = evidence
    }
}
