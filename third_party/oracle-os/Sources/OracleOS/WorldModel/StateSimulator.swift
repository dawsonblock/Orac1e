import Foundation

/// Simulates the predicted effect of an action on the current world model
/// snapshot without actually executing it. Used by the planner to evaluate
/// candidate plans before committing.
public final class StateSimulator: @unchecked Sendable {

    public init() {}

    /// Predict what the world model would look like after executing an operator.
    public func predict(
        from snapshot: WorldModelSnapshot,
        operator op: Operator,
        state: ReasoningPlanningState
    ) -> StateSimulationResult {
        var predicted = snapshot
        var changes: [String] = []
        var confidence: Double = 0.5

        switch op.kind {
        case .dismissModal:
            if snapshot.modalPresent {
                predicted = snapshot.copy(modalPresent: false)
                changes.append("modal dismissed")
                confidence = 0.85
            } else {
                changes.append("no modal to dismiss")
                confidence = 0.1
            }

        case .focusWindow, .openApplication:
            let targetApp = state.targetApplication ?? "unknown"
            predicted = snapshot.copy(activeApplication: .some(targetApp))
            changes.append("focused \(targetApp)")
            confidence = 0.75

        case .runTests:
            changes.append("tests executed")
            confidence = 0.6

        case .applyPatch:
            predicted = snapshot.copy(isGitDirty: true)
            changes.append("patch applied, repo dirty")
            confidence = 0.65

        case .buildProject:
            changes.append("build executed")
            confidence = 0.6

        case .rollbackPatch, .revertPatch:
            predicted = snapshot.copy(isGitDirty: false)
            changes.append("patch reverted")
            confidence = 0.8

        default:
            changes.append("action executed: \(op.kind.rawValue)")
            confidence = 0.4
        }

        return StateSimulationResult(
            predictedSnapshot: predicted,
            changes: changes,
            confidence: confidence
        )
    }
}

/// The result of simulating a single operator's effect on the world model.
public struct StateSimulationResult: Sendable {
    public let predictedSnapshot: WorldModelSnapshot
    public let changes: [String]
    public let confidence: Double

    public init(
        predictedSnapshot: WorldModelSnapshot,
        changes: [String] = [],
        confidence: Double = 0.5
    ) {
        self.predictedSnapshot = predictedSnapshot
        self.changes = changes
        self.confidence = confidence
    }
}
