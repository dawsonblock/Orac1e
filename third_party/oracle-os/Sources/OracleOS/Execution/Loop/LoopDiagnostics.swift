import Foundation

public enum LoopPreparationOutcome: String, Sendable, Equatable {
    case pending
    case ready
    case failed
}

public enum LoopPolicyOutcome: String, Sendable, Equatable {
    case pending
    case allowed
    case blocked
}

public enum LoopExecutionOutcome: String, Sendable, Equatable {
    case pending
    case succeeded
    case failed
    case skipped
}

public enum LoopRecoveryOutcome: String, Sendable, Equatable {
    case none
    case attempted
    case succeeded
    case failed
    case skipped
}

public struct LoopStepSummary: Sendable, Equatable, Identifiable {
    public let id: String
    public let stepIndex: Int
    public let source: PlannerSource
    public let skillName: String
    public let workflowID: String?
    public let experimentID: String?
    public let pathEdgeIDs: [String]
    public let currentEdgeID: String?
    public let fallbackReason: String?
    public let success: Bool
    public let failure: FailureClass?
    public let recoveryStrategy: String?
    public let preparationOutcome: LoopPreparationOutcome
    public let policyOutcome: LoopPolicyOutcome
    public let executionOutcome: LoopExecutionOutcome
    public let recoveryOutcome: LoopRecoveryOutcome
    public let terminationReason: LoopTerminationReason?
    public let notes: [String]

    public init(
        id: String = UUID().uuidString,
        stepIndex: Int,
        source: PlannerSource,
        skillName: String,
        workflowID: String? = nil,
        experimentID: String? = nil,
        pathEdgeIDs: [String] = [],
        currentEdgeID: String? = nil,
        fallbackReason: String? = nil,
        success: Bool,
        failure: FailureClass? = nil,
        recoveryStrategy: String? = nil,
        preparationOutcome: LoopPreparationOutcome = .pending,
        policyOutcome: LoopPolicyOutcome = .pending,
        executionOutcome: LoopExecutionOutcome = .pending,
        recoveryOutcome: LoopRecoveryOutcome = .none,
        terminationReason: LoopTerminationReason? = nil,
        notes: [String] = []
    ) {
        self.id = id
        self.stepIndex = stepIndex
        self.source = source
        self.skillName = skillName
        self.workflowID = workflowID
        self.experimentID = experimentID
        self.pathEdgeIDs = pathEdgeIDs
        self.currentEdgeID = currentEdgeID
        self.fallbackReason = fallbackReason
        self.success = success
        self.failure = failure
        self.recoveryStrategy = recoveryStrategy
        self.preparationOutcome = preparationOutcome
        self.policyOutcome = policyOutcome
        self.executionOutcome = executionOutcome
        self.recoveryOutcome = recoveryOutcome
        self.terminationReason = terminationReason
        self.notes = notes
    }
}

public struct LoopDiagnostics: Sendable, Equatable {
    public var stepSummaries: [LoopStepSummary]

    public init(stepSummaries: [LoopStepSummary] = []) {
        self.stepSummaries = stepSummaries
    }

    public mutating func append(_ summary: LoopStepSummary) {
        stepSummaries.append(summary)
    }

    public mutating func beginStep(
        stepIndex: Int,
        decision: PlannerDecision
    ) {
        guard stepSummaries.contains(where: { $0.stepIndex == stepIndex }) == false else {
            return
        }

        append(
            LoopStepSummary(
                stepIndex: stepIndex,
                source: decision.source,
                skillName: decision.skillName,
                workflowID: decision.workflowID,
                experimentID: decision.experimentSpec?.id,
                pathEdgeIDs: decision.pathEdgeIDs,
                currentEdgeID: decision.currentEdgeID,
                fallbackReason: decision.fallbackReason,
                success: false,
                notes: decision.notes
            )
        )
    }

    public mutating func recordPreparation(
        stepIndex: Int,
        outcome: LoopPreparationOutcome,
        failure: FailureClass? = nil,
        notes: [String] = []
    ) {
        update(stepIndex: stepIndex) { summary in
            LoopStepSummary(
                id: summary.id,
                stepIndex: summary.stepIndex,
                source: summary.source,
                skillName: summary.skillName,
                workflowID: summary.workflowID,
                experimentID: summary.experimentID,
                pathEdgeIDs: summary.pathEdgeIDs,
                currentEdgeID: summary.currentEdgeID,
                fallbackReason: summary.fallbackReason,
                success: summary.success,
                failure: failure ?? summary.failure,
                recoveryStrategy: summary.recoveryStrategy,
                preparationOutcome: outcome,
                policyOutcome: summary.policyOutcome,
                executionOutcome: summary.executionOutcome,
                recoveryOutcome: summary.recoveryOutcome,
                terminationReason: summary.terminationReason,
                notes: summary.notes + notes
            )
        }
    }

    public mutating func recordPolicy(
        stepIndex: Int,
        outcome: LoopPolicyOutcome,
        notes: [String] = []
    ) {
        update(stepIndex: stepIndex) { summary in
            LoopStepSummary(
                id: summary.id,
                stepIndex: summary.stepIndex,
                source: summary.source,
                skillName: summary.skillName,
                workflowID: summary.workflowID,
                experimentID: summary.experimentID,
                pathEdgeIDs: summary.pathEdgeIDs,
                currentEdgeID: summary.currentEdgeID,
                fallbackReason: summary.fallbackReason,
                success: summary.success,
                failure: summary.failure,
                recoveryStrategy: summary.recoveryStrategy,
                preparationOutcome: summary.preparationOutcome,
                policyOutcome: outcome,
                executionOutcome: summary.executionOutcome,
                recoveryOutcome: summary.recoveryOutcome,
                terminationReason: summary.terminationReason,
                notes: summary.notes + notes
            )
        }
    }

    public mutating func recordExecution(
        stepIndex: Int,
        success: Bool,
        failure: FailureClass? = nil,
        notes: [String] = []
    ) {
        update(stepIndex: stepIndex) { summary in
            LoopStepSummary(
                id: summary.id,
                stepIndex: summary.stepIndex,
                source: summary.source,
                skillName: summary.skillName,
                workflowID: summary.workflowID,
                experimentID: summary.experimentID,
                pathEdgeIDs: summary.pathEdgeIDs,
                currentEdgeID: summary.currentEdgeID,
                fallbackReason: summary.fallbackReason,
                success: success,
                failure: failure ?? summary.failure,
                recoveryStrategy: summary.recoveryStrategy,
                preparationOutcome: summary.preparationOutcome,
                policyOutcome: summary.policyOutcome == .pending ? .allowed : summary.policyOutcome,
                executionOutcome: success ? .succeeded : .failed,
                recoveryOutcome: summary.recoveryOutcome,
                terminationReason: summary.terminationReason,
                notes: summary.notes + notes
            )
        }
    }

    public mutating func recordExecutionSkipped(
        stepIndex: Int,
        failure: FailureClass? = nil,
        notes: [String] = []
    ) {
        update(stepIndex: stepIndex) { summary in
            LoopStepSummary(
                id: summary.id,
                stepIndex: summary.stepIndex,
                source: summary.source,
                skillName: summary.skillName,
                workflowID: summary.workflowID,
                experimentID: summary.experimentID,
                pathEdgeIDs: summary.pathEdgeIDs,
                currentEdgeID: summary.currentEdgeID,
                fallbackReason: summary.fallbackReason,
                success: false,
                failure: failure ?? summary.failure,
                recoveryStrategy: summary.recoveryStrategy,
                preparationOutcome: summary.preparationOutcome,
                policyOutcome: summary.policyOutcome,
                executionOutcome: .skipped,
                recoveryOutcome: summary.recoveryOutcome,
                terminationReason: summary.terminationReason,
                notes: summary.notes + notes
            )
        }
    }

    public mutating func recordRecovery(
        stepIndex: Int,
        strategyName: String?,
        success: Bool,
        failure: FailureClass? = nil,
        notes: [String] = []
    ) {
        update(stepIndex: stepIndex) { summary in
            LoopStepSummary(
                id: summary.id,
                stepIndex: summary.stepIndex,
                source: summary.source,
                skillName: summary.skillName,
                workflowID: summary.workflowID,
                experimentID: summary.experimentID,
                pathEdgeIDs: summary.pathEdgeIDs,
                currentEdgeID: summary.currentEdgeID,
                fallbackReason: summary.fallbackReason,
                success: success ? summary.success : false,
                failure: failure ?? summary.failure,
                recoveryStrategy: strategyName ?? summary.recoveryStrategy,
                preparationOutcome: summary.preparationOutcome,
                policyOutcome: summary.policyOutcome,
                executionOutcome: summary.executionOutcome == .pending ? .skipped : summary.executionOutcome,
                recoveryOutcome: success ? .succeeded : .failed,
                terminationReason: summary.terminationReason,
                notes: summary.notes + notes
            )
        }
    }

    public mutating func recordTermination(
        stepIndex: Int?,
        reason: LoopTerminationReason
    ) {
        guard let stepIndex else { return }
        update(stepIndex: stepIndex) { summary in
            LoopStepSummary(
                id: summary.id,
                stepIndex: summary.stepIndex,
                source: summary.source,
                skillName: summary.skillName,
                workflowID: summary.workflowID,
                experimentID: summary.experimentID,
                pathEdgeIDs: summary.pathEdgeIDs,
                currentEdgeID: summary.currentEdgeID,
                fallbackReason: summary.fallbackReason,
                success: summary.success,
                failure: summary.failure,
                recoveryStrategy: summary.recoveryStrategy,
                preparationOutcome: summary.preparationOutcome,
                policyOutcome: summary.policyOutcome,
                executionOutcome: summary.executionOutcome,
                recoveryOutcome: summary.recoveryOutcome,
                terminationReason: reason,
                notes: summary.notes
            )
        }
    }

    private mutating func update(
        stepIndex: Int,
        transform: (LoopStepSummary) -> LoopStepSummary
    ) {
        guard let index = stepSummaries.lastIndex(where: { $0.stepIndex == stepIndex }) else {
            return
        }
        stepSummaries[index] = transform(stepSummaries[index])
    }

    public static let empty = LoopDiagnostics()
}
