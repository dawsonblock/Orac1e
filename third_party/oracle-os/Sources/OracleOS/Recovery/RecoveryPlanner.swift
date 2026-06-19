import Foundation

public struct RecoveryPlan: Sendable {
    public let failureClass: FailureClass
    public let recoveryOperators: [Operator]
    public let estimatedRecoveryProbability: Double
    public let notes: [String]

    public init(
        failureClass: FailureClass,
        recoveryOperators: [Operator],
        estimatedRecoveryProbability: Double,
        notes: [String] = []
    ) {
        self.failureClass = failureClass
        self.recoveryOperators = recoveryOperators
        self.estimatedRecoveryProbability = estimatedRecoveryProbability
        self.notes = notes
    }
}

public final class RecoveryPlanner: @unchecked Sendable {

    public init() {}

    public func plan(
        failure: FailureClass,
        state: ReasoningPlanningState
    ) -> [RecoveryPlan] {
        let operators = recoveryOperators(for: failure, state: state)
        guard !operators.isEmpty else { return [] }

        return operators.map { ops in
            let probability = estimatedProbability(
                operators: ops,
                failure: failure,
                state: state
            )
            return RecoveryPlan(
                failureClass: failure,
                recoveryOperators: ops,
                estimatedRecoveryProbability: probability,
                notes: ops.map { "recovery: \($0.name)" }
            )
        }
        .sorted { $0.estimatedRecoveryProbability > $1.estimatedRecoveryProbability }
    }

    public func bestRecoveryPlan(
        failure: FailureClass,
        state: ReasoningPlanningState
    ) -> RecoveryPlan? {
        plan(failure: failure, state: state).first
    }

    /// Generate recovery plans bounded by the recovery strategy's allowed operator families.
    ///
    /// When recovery is a true strategy (``StrategyKind.recoveryMode``), the recovery
    /// planner produces plans only within the recovery-allowed operator families,
    /// preventing leakage into unrelated actions.
    public func strategyBoundedPlan(
        failure: FailureClass,
        state: ReasoningPlanningState,
        selectedStrategy: SelectedStrategy
    ) -> [RecoveryPlan] {
        let allPlans = plan(failure: failure, state: state)

        // Filter recovery operators to only those allowed by the strategy.
        return allPlans.compactMap { recoveryPlan in
            let filteredOps = recoveryPlan.recoveryOperators.filter { op in
                selectedStrategy.allows(op.kind.operatorFamily)
            }
            guard !filteredOps.isEmpty else { return nil }
            return RecoveryPlan(
                failureClass: recoveryPlan.failureClass,
                recoveryOperators: filteredOps,
                estimatedRecoveryProbability: recoveryPlan.estimatedRecoveryProbability,
                notes: recoveryPlan.notes + ["strategy-bounded recovery"]
            )
        }
    }

    private func recoveryOperators(
        for failure: FailureClass,
        state: ReasoningPlanningState
    ) -> [[Operator]] {
        switch failure {
        case .elementNotFound, .targetMissing:
            var plans: [[Operator]] = []
            let retryOp = Operator(kind: .retryWithAlternateTarget)
            if retryOp.precondition(state) {
                plans.append([retryOp])
            }
            return plans

        case .elementAmbiguous:
            var plans: [[Operator]] = []
            let retryOp = Operator(kind: .retryWithAlternateTarget)
            if retryOp.precondition(state) {
                plans.append([retryOp])
            }
            return plans

        case .wrongFocus:
            var plans: [[Operator]] = []
            let focusOp = Operator(kind: .focusWindow)
            if focusOp.precondition(state) {
                plans.append([focusOp])
            }
            let restartOp = Operator(kind: .restartApplication)
            if restartOp.precondition(state) {
                plans.append([restartOp])
            }
            return plans

        case .modalBlocking, .unexpectedDialog:
            var plans: [[Operator]] = []
            let dismissOp = Operator(kind: .dismissModal)
            if dismissOp.precondition(state) {
                plans.append([dismissOp])
            }
            return plans

        case .patchApplyFailed:
            var plans: [[Operator]] = []
            let rollbackOp = Operator(kind: .rollbackPatch)
            if rollbackOp.precondition(state) {
                plans.append([rollbackOp])
            }
            let revertOp = Operator(kind: .revertPatch)
            if revertOp.precondition(state) {
                plans.append([revertOp])
            }
            return plans

        case .testFailed:
            var plans: [[Operator]] = []
            let rerunOp = Operator(kind: .rerunTests)
            if rerunOp.precondition(state) {
                plans.append([rerunOp])
            }
            let rollbackAndRerun: [Operator] = [
                Operator(kind: .rollbackPatch),
                Operator(kind: .rerunTests),
            ]
            if rollbackAndRerun.allSatisfy({ $0.precondition(state) }) {
                plans.append(rollbackAndRerun)
            }
            return plans

        case .buildFailed:
            var plans: [[Operator]] = []
            let rollbackOp = Operator(kind: .rollbackPatch)
            if rollbackOp.precondition(state) {
                plans.append([rollbackOp, Operator(kind: .buildProject)])
            }
            return plans

        case .navigationFailed:
            var plans: [[Operator]] = []
            let focusOp = Operator(kind: .focusWindow)
            if focusOp.precondition(state) {
                plans.append([focusOp])
            }
            let navOp = Operator(kind: .navigateBrowser)
            if navOp.precondition(state) {
                plans.append([navOp])
            }
            return plans

        case .permissionBlocked:
            var plans: [[Operator]] = []
            let dismissOp = Operator(kind: .dismissModal)
            if dismissOp.precondition(state) {
                plans.append([dismissOp])
            }
            return plans

        case .environmentMismatch:
            var plans: [[Operator]] = []
            let restartOp = Operator(kind: .restartApplication)
            if restartOp.precondition(state) {
                plans.append([restartOp])
            }
            return plans

        case .actionFailed, .verificationFailed, .staleObservation,
             .workspaceScopeViolation, .gitPolicyBlocked, .noRelevantFiles,
             .ambiguousEditTarget:
            return []

        case .loopStalled:
            // Force a refocus so the AX tree rebuilds, giving the planner a
            // fresh observation to diversify from.
            var plans: [[Operator]] = []
            let focusOp = Operator(kind: .focusWindow)
            if focusOp.precondition(state) {
                plans.append([focusOp])
            }
            return plans

        case .workflowReplayFailure:
            var plans: [[Operator]] = []
            let focusOp = Operator(kind: .focusWindow)
            if focusOp.precondition(state) {
                plans.append([focusOp])
            }
            let navOp = Operator(kind: .navigateBrowser)
            if navOp.precondition(state) {
                plans.append([navOp])
            }
            return plans
        }
    }

    private func estimatedProbability(
        operators: [Operator],
        failure: FailureClass,
        state: ReasoningPlanningState
    ) -> Double {
        var probability = 0.5

        switch failure {
        case .modalBlocking, .unexpectedDialog:
            probability += state.modalPresent ? 0.3 : 0
        case .wrongFocus:
            probability += state.targetApplication != nil ? 0.25 : 0
        case .patchApplyFailed:
            probability += state.patchApplied ? 0.2 : 0
        case .testFailed:
            probability += state.repoOpen ? 0.15 : 0
        case .workflowReplayFailure:
            probability += state.targetApplication != nil ? 0.15 : 0
        default:
            break
        }

        let totalRisk = operators.reduce(0.0) { $0 + $1.risk }
        probability -= totalRisk * 0.3

        return min(max(probability, 0.05), 0.95)
    }

    /// Graph-based recovery: when an edge fails, re-evaluate alternate
    /// edges from the same task-graph node instead of using a separate
    /// recovery channel. This keeps recovery within the graph substrate.
    public func graphRecoveryEdges(
        failedEdgeID: String,
        taskGraphStore: TaskLedgerStore
    ) -> [TaskRecordEdge] {
        taskGraphStore.recoveryEdges(excludingEdgeID: failedEdgeID)
            .sorted { $0.successProbability > $1.successProbability }
    }
}
