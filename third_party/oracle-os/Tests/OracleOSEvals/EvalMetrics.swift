import Foundation

struct EvalMetrics {
    let successRate: Double
    let firstPassSuccessRate: Double
    let averageSteps: Double
    let recoverySuccessRate: Double
    let graphReuseRatio: Double
    let workflowReuseRatio: Double
    let ambiguityFailureCount: Int
    let patchSelectionSuccessRate: Double
    let recoveryReuseRatio: Double
    let plannerReasoningRatio: Double
    let planStability: Double
    let wrongTargetRate: Double
    let recoveryLoopCount: Int

    init(
        successRate: Double,
        firstPassSuccessRate: Double,
        averageSteps: Double,
        recoverySuccessRate: Double,
        graphReuseRatio: Double,
        workflowReuseRatio: Double,
        ambiguityFailureCount: Int,
        patchSelectionSuccessRate: Double,
        recoveryReuseRatio: Double = 0,
        plannerReasoningRatio: Double = 0,
        planStability: Double = 0,
        wrongTargetRate: Double = 0,
        recoveryLoopCount: Int = 0
    ) {
        self.successRate = successRate
        self.firstPassSuccessRate = firstPassSuccessRate
        self.averageSteps = averageSteps
        self.recoverySuccessRate = recoverySuccessRate
        self.graphReuseRatio = graphReuseRatio
        self.workflowReuseRatio = workflowReuseRatio
        self.ambiguityFailureCount = ambiguityFailureCount
        self.patchSelectionSuccessRate = patchSelectionSuccessRate
        self.recoveryReuseRatio = recoveryReuseRatio
        self.plannerReasoningRatio = plannerReasoningRatio
        self.planStability = planStability
        self.wrongTargetRate = wrongTargetRate
        self.recoveryLoopCount = recoveryLoopCount
    }

    var comparisonFields: [(String, String)] {
        [
            ("success_rate", percent(successRate)),
            ("first_pass_success_rate", percent(firstPassSuccessRate)),
            ("average_steps", String(format: "%.2f", averageSteps)),
            ("recovery_success_rate", percent(recoverySuccessRate)),
            ("graph_reuse_ratio", percent(graphReuseRatio)),
            ("workflow_reuse_ratio", percent(workflowReuseRatio)),
            ("ambiguity_failure_count", "\(ambiguityFailureCount)"),
            ("patch_selection_success_rate", percent(patchSelectionSuccessRate)),
            ("recovery_reuse_ratio", percent(recoveryReuseRatio)),
            ("planner_reasoning_ratio", percent(plannerReasoningRatio)),
            ("plan_stability", percent(planStability)),
            ("wrong_target_rate", percent(wrongTargetRate)),
            ("recovery_loop_count", "\(recoveryLoopCount)"),
        ]
    }

    func summary(taskName: String) -> String {
        let fields = comparisonFields
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: " ")
        return "\(taskName): \(fields)"
    }

    func regressions(against baseline: EvalMetrics, thresholds: RegressionThresholds = RegressionThresholds()) -> [String] {
        var regressions: [String] = []
        if successRate < baseline.successRate - thresholds.successRateDrop {
            regressions.append("success_rate regressed from \(percent(baseline.successRate)) to \(percent(successRate))")
        }
        if recoverySuccessRate < baseline.recoverySuccessRate - thresholds.recoveryRateDrop {
            regressions.append("recovery_success_rate regressed from \(percent(baseline.recoverySuccessRate)) to \(percent(recoverySuccessRate))")
        }
        if workflowReuseRatio < baseline.workflowReuseRatio - thresholds.workflowReuseDrop {
            regressions.append("workflow_reuse_ratio regressed from \(percent(baseline.workflowReuseRatio)) to \(percent(workflowReuseRatio))")
        }
        if ambiguityFailureCount > baseline.ambiguityFailureCount + thresholds.ambiguityFailureIncrease {
            regressions.append("ambiguity_failure_count increased from \(baseline.ambiguityFailureCount) to \(ambiguityFailureCount)")
        }
        if patchSelectionSuccessRate < baseline.patchSelectionSuccessRate - thresholds.patchSelectionDrop {
            regressions.append("patch_selection_success_rate regressed from \(percent(baseline.patchSelectionSuccessRate)) to \(percent(patchSelectionSuccessRate))")
        }
        if graphReuseRatio < baseline.graphReuseRatio - thresholds.graphReuseDrop {
            regressions.append("graph_reuse_ratio regressed from \(percent(baseline.graphReuseRatio)) to \(percent(graphReuseRatio))")
        }
        if recoveryReuseRatio < baseline.recoveryReuseRatio - thresholds.recoveryReuseDrop {
            regressions.append("recovery_reuse_ratio regressed from \(percent(baseline.recoveryReuseRatio)) to \(percent(recoveryReuseRatio))")
        }
        if averageSteps > baseline.averageSteps + thresholds.averageStepsIncrease {
            regressions.append("average_steps spiked from \(String(format: "%.2f", baseline.averageSteps)) to \(String(format: "%.2f", averageSteps))")
        }
        if wrongTargetRate > baseline.wrongTargetRate + thresholds.wrongTargetRateIncrease {
            regressions.append("wrong_target_rate increased from \(percent(baseline.wrongTargetRate)) to \(percent(wrongTargetRate))")
        }
        if recoveryLoopCount > baseline.recoveryLoopCount + thresholds.recoveryLoopIncrease {
            regressions.append("recovery_loop_count increased from \(baseline.recoveryLoopCount) to \(recoveryLoopCount)")
        }
        if planStability < baseline.planStability - thresholds.planStabilityDrop {
            regressions.append("plan_stability regressed from \(percent(baseline.planStability)) to \(percent(planStability))")
        }
        return regressions
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

struct RegressionThresholds {
    let successRateDrop: Double
    let recoveryRateDrop: Double
    let workflowReuseDrop: Double
    let ambiguityFailureIncrease: Int
    let patchSelectionDrop: Double
    let graphReuseDrop: Double
    let recoveryReuseDrop: Double
    let averageStepsIncrease: Double
    let wrongTargetRateIncrease: Double
    let recoveryLoopIncrease: Int
    let planStabilityDrop: Double

    init(
        successRateDrop: Double = 0.05,
        recoveryRateDrop: Double = 0.1,
        workflowReuseDrop: Double = 0.1,
        ambiguityFailureIncrease: Int = 2,
        patchSelectionDrop: Double = 0.1,
        graphReuseDrop: Double = 0.1,
        recoveryReuseDrop: Double = 0.15,
        averageStepsIncrease: Double = 5.0,
        wrongTargetRateIncrease: Double = 0.05,
        recoveryLoopIncrease: Int = 3,
        planStabilityDrop: Double = 0.1
    ) {
        self.successRateDrop = successRateDrop
        self.recoveryRateDrop = recoveryRateDrop
        self.workflowReuseDrop = workflowReuseDrop
        self.ambiguityFailureIncrease = ambiguityFailureIncrease
        self.patchSelectionDrop = patchSelectionDrop
        self.graphReuseDrop = graphReuseDrop
        self.recoveryReuseDrop = recoveryReuseDrop
        self.averageStepsIncrease = averageStepsIncrease
        self.wrongTargetRateIncrease = wrongTargetRateIncrease
        self.recoveryLoopIncrease = recoveryLoopIncrease
        self.planStabilityDrop = planStabilityDrop
    }
}
