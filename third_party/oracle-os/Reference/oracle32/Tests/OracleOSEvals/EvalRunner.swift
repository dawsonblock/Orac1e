import Foundation

enum EvalRunner {
    @MainActor
    static func run(task: EvalTask) async -> EvalReport {
        var successes = 0
        var firstPassSuccesses = 0
        var totalSteps = 0
        var recoveryAttempts = 0
        var successfulRecoveries = 0
        var graphReuseCount = 0
        var workflowReuseCount = 0
        var ambiguityFailures = 0
        var patchSelections = 0
        var recoveryReuseCount = 0
        var plannerReasoningCount = 0
        var wrongTargetCount = 0
        var recoveryLoops = 0
        var planSourceSets: [Set<String>] = []

        for index in 0..<task.runs {
            let snapshot = await task.executeRun(index)
            if snapshot.succeeded {
                successes += 1
            }
            if snapshot.firstPassSucceeded {
                firstPassSuccesses += 1
            }
            totalSteps += snapshot.outcome.steps
            if snapshot.recoveryAttempted {
                recoveryAttempts += 1
            }
            if snapshot.recoverySucceeded {
                successfulRecoveries += 1
            }
            if snapshot.usedStableGraph {
                graphReuseCount += 1
            }
            if snapshot.usedWorkflow {
                workflowReuseCount += 1
            }
            if snapshot.outcome.lastFailure == .elementAmbiguous {
                ambiguityFailures += 1
            }
            if snapshot.patchSelectionSucceeded {
                patchSelections += 1
            }
            if snapshot.recoveryReused {
                recoveryReuseCount += 1
            }
            if snapshot.usedPlannerReasoning {
                plannerReasoningCount += 1
            }
            if snapshot.outcome.lastFailure == .targetMissing || snapshot.outcome.lastFailure == .elementNotFound {
                wrongTargetCount += 1
            }
            recoveryLoops += snapshot.recoveryLoopCount
            planSourceSets.append(snapshot.planSourceSet)
        }

        let runs = max(task.runs, 1)
        let planStability = Self.computePlanStability(planSourceSets)
        let metrics = EvalMetrics(
            successRate: Double(successes) / Double(runs),
            firstPassSuccessRate: Double(firstPassSuccesses) / Double(runs),
            averageSteps: Double(totalSteps) / Double(runs),
            recoverySuccessRate: recoveryAttempts == 0 ? 0 : Double(successfulRecoveries) / Double(recoveryAttempts),
            graphReuseRatio: Double(graphReuseCount) / Double(runs),
            workflowReuseRatio: Double(workflowReuseCount) / Double(runs),
            ambiguityFailureCount: ambiguityFailures,
            patchSelectionSuccessRate: Double(patchSelections) / Double(runs),
            recoveryReuseRatio: Double(recoveryReuseCount) / Double(runs),
            plannerReasoningRatio: Double(plannerReasoningCount) / Double(runs),
            planStability: planStability,
            wrongTargetRate: Double(wrongTargetCount) / Double(runs),
            recoveryLoopCount: recoveryLoops
        )
        return EvalReport(taskName: task.name, family: task.family, runs: task.runs, metrics: metrics)
    }

    private static func computePlanStability(_ sets: [Set<String>]) -> Double {
        guard sets.count >= 2 else { return 1.0 }
        var matchCount = 0
        var pairCount = 0
        for i in 0..<sets.count {
            for j in (i + 1)..<sets.count {
                pairCount += 1
                if sets[i] == sets[j] {
                    matchCount += 1
                }
            }
        }
        guard pairCount > 0 else { return 1.0 }
        return Double(matchCount) / Double(pairCount)
    }
}
