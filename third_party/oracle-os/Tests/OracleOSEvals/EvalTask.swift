import Foundation
@testable import OracleOS

enum EvalTaskFamily: String {
    case operatorTask = "operator"
    case codingTask = "coding"
    case hybridTask = "hybrid"
    case ambiguousUI = "ambiguous-ui"
    case dialogStorm = "dialog-storm"
    case recoveryLoop = "recovery-loop"
    case patchFailure = "patch-failure"
    case workflowDrift = "workflow-drift"
}

@MainActor
struct EvalTask {
    let name: String
    let family: EvalTaskFamily
    let runs: Int
    let executeRun: (Int) async -> EvalRunSnapshot
}

struct EvalRunSnapshot {
    let outcome: LoopOutcome
    let usedStableGraph: Bool
    let usedWorkflow: Bool
    let recoveryAttempted: Bool
    let patchSelectionSucceeded: Bool
    let recoveryReused: Bool
    let usedPlannerReasoning: Bool
    let recoveryLoopCount: Int
    let planSourceSet: Set<String>
    let successOverride: Bool?

    init(
        outcome: LoopOutcome,
        usedStableGraph: Bool,
        usedWorkflow: Bool = false,
        recoveryAttempted: Bool? = nil,
        patchSelectionSucceeded: Bool = false,
        recoveryReused: Bool = false,
        usedPlannerReasoning: Bool = false,
        recoveryLoopCount: Int = 0,
        planSourceSet: Set<String> = [],
        successOverride: Bool? = nil
    ) {
        self.outcome = outcome
        self.usedStableGraph = usedStableGraph
        self.usedWorkflow = usedWorkflow
        self.recoveryAttempted = recoveryAttempted ?? (outcome.recoveries > 0)
        self.patchSelectionSucceeded = patchSelectionSucceeded
        self.recoveryReused = recoveryReused
        self.usedPlannerReasoning = usedPlannerReasoning
        self.recoveryLoopCount = recoveryLoopCount
        self.planSourceSet = planSourceSet
        self.successOverride = successOverride
    }

    var succeeded: Bool {
        if let successOverride {
            return successOverride
        }

        if outcome.reason == .goalAchieved {
            return true
        }

        if patchSelectionSucceeded || usedWorkflow || usedStableGraph {
            return true
        }

        if recoveryAttempted && outcome.lastFailure == nil {
            return true
        }

        return false
    }

    var recoverySucceeded: Bool {
        recoveryAttempted && succeeded
    }

    var firstPassSucceeded: Bool {
        succeeded && !recoveryAttempted
    }
}
