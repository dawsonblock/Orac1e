import Foundation

/// Represents a possible or executed transition between two ``TaskRecord``s.
///
/// ``TaskRecordEdge`` tracks both candidate (planned but not yet executed) and
/// executed transitions. Evidence accumulates over repeated attempts so the
/// planner can estimate ``successProbability`` for path scoring.
public final class TaskRecordEdge: @unchecked Sendable {
    public let id: String
    public let fromNodeID: String
    public let toNodeID: String
    public let action: String
    public let actionContractID: String?
    public let operatorFamily: OperatorFamily
    public private(set) var status: TaskRecordEdgeStatus
    public private(set) var successCount: Int
    public private(set) var failureCount: Int
    public private(set) var totalCost: Double
    public private(set) var totalLatencyMs: Int
    public private(set) var lastAttemptTimestamp: TimeInterval?
    public private(set) var risk: Double
    public let createdTimestamp: TimeInterval

    public init(
        id: String = UUID().uuidString,
        fromNodeID: String,
        toNodeID: String,
        action: String,
        actionContractID: String? = nil,
        operatorFamily: OperatorFamily? = nil,
        status: TaskRecordEdgeStatus = .candidate,
        successCount: Int = 0,
        failureCount: Int = 0,
        totalCost: Double = 0,
        totalLatencyMs: Int = 0,
        lastAttemptTimestamp: TimeInterval? = nil,
        risk: Double = 0,
        createdTimestamp: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.fromNodeID = fromNodeID
        self.toNodeID = toNodeID
        self.action = action
        self.actionContractID = actionContractID
        self.operatorFamily = operatorFamily ?? LedgerNavigator.operatorFamilyForAction(action)
        self.status = status
        self.successCount = successCount
        self.failureCount = failureCount
        self.totalCost = totalCost
        self.totalLatencyMs = totalLatencyMs
        self.lastAttemptTimestamp = lastAttemptTimestamp
        self.risk = risk
        self.createdTimestamp = createdTimestamp
    }

    // MARK: - Evidence

    public var attempts: Int {
        successCount + failureCount
    }

    public var successProbability: Double {
        guard attempts > 0 else { return 0 }
        return Double(successCount) / Double(attempts)
    }

    public var averageLatencyMs: Double {
        guard attempts > 0 else { return 0 }
        return Double(totalLatencyMs) / Double(attempts)
    }

    public var averageCost: Double {
        guard attempts > 0 else { return 0 }
        return totalCost / Double(attempts)
    }

    // MARK: - Recording

    public func recordSuccess(latencyMs: Int = 0, cost: Double = 0) {
        successCount += 1
        totalLatencyMs += latencyMs
        totalCost += cost
        lastAttemptTimestamp = Date().timeIntervalSince1970
        status = .executedSuccess
    }

    public func recordFailure(latencyMs: Int = 0, cost: Double = 0) {
        failureCount += 1
        totalLatencyMs += latencyMs
        totalCost += cost
        lastAttemptTimestamp = Date().timeIntervalSince1970
        status = .executedFailure
    }

    public func markAbandoned() {
        status = .abandoned
    }

    public func updateRisk(_ newRisk: Double) {
        risk = max(0, min(1, newRisk))
    }
}

/// Status of a ``TaskRecordEdge``.
public enum TaskRecordEdgeStatus: String, Codable, Sendable {
    case candidate
    case executedSuccess = "executed_success"
    case executedFailure = "executed_failure"
    case abandoned
}
