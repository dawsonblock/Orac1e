import Foundation
@testable import OracleOS

/// Orchestrates exactly one full run of the official evaluation benchmark suite.
///
/// It instantiates all benchmark task families (coding, ambiguous UI, dialog storms,
/// patch recovery, etc.), runs them through ``EvalRunner``, and aggregates the
/// results. The final aggregated metrics are then compared against the strict
/// ``BenchmarkBaseline.current``.
///
/// Any major refactor to the AgentLoop, Planner, Executor, or Runtime MUST
/// cleanly pass the `runAll()` threshold below before merging.
@MainActor
public struct BenchmarkRunner {
    
    public init() {}
    
    /// Executes all benchmark suites and compares the aggregated metrics to the baseline.
    ///
    /// - Returns: A `BaselineResult` indicating whether the runtime still meets
    ///   the required performance, stability, and success rate tolerances.
    public func runAll() async -> BaselineResult {
        // Collect all standard eval suites
        let tasks: [EvalTask] = [
            HybridBenchmarks.buildSuite(),
            OperatorBenchmarks.buildSuite(),
            UpgradeBenchmarks.buildSuite(),
            RecoveryLoopTasks.buildSuite(),
            PatchFailureTasks.buildSuite(),
            DialogStormTasks.buildSuite(),
            AmbiguousUITasks.buildSuite(),
            WorkflowDriftTasks.buildSuite(),
            CodingBenchmarks.buildSuite()
        ].flatMap { $0 }
        
        guard !tasks.isEmpty else {
            return BaselineResult(passed: false, violations: ["No benchmark tasks found."])
        }
        
        var totalSuccesses = 0
        var totalSteps = 0
        var totalRecoveryAttempts = 0
        var totalSuccessfulRecoveries = 0
        var totalWrongTargetCount = 0
        var totalPatchSelections = 0
        
        // Execute all tasks and sum the raw counters
        for task in tasks {
            let report = await EvalRunner.run(task: task)
            
            // Reconstruct absolute counts from the report metrics and task runs
            let runs = Double(task.runs)
            totalSuccesses += Int((report.metrics.successRate * runs).rounded())
            totalSteps += Int((report.metrics.averageSteps * runs).rounded())
            
            // Recovery success rate is only non-zero if attempts > 0, 
            // but we can't easily extract exact attempt counts from the ratio.
            // For the benchmark aggregate, we'll estimate the raw counts based on the recovery rate
            // and loop count signals, though in a real system we'd extract the raw sums directly 
            // from an extended EvalReport.
            totalWrongTargetCount += Int((report.metrics.wrongTargetRate * runs).rounded())
            totalPatchSelections += Int((report.metrics.patchSelectionSuccessRate * runs).rounded())
            
            // Estimate recovery attempts based on loop count (not perfectly accurate, but serves the baseline check)
            let estimatedAttempts = report.metrics.recoveryLoopCount
            totalRecoveryAttempts += estimatedAttempts
            totalSuccessfulRecoveries += Int((report.metrics.recoverySuccessRate * Double(estimatedAttempts)).rounded())
        }
        
        let aggregateRuns = Double(tasks.reduce(0) { $0 + $1.runs })
        
        let aggregateSuccessRate = Double(totalSuccesses) / aggregateRuns
        let aggregateAverageSteps = Double(totalSteps) / aggregateRuns
        let aggregateWrongTargetRate = Double(totalWrongTargetCount) / aggregateRuns
        let aggregatePatchSuccessRate = Double(totalPatchSelections) / aggregateRuns
        
        // Regression rate is derived inversely from first_pass_success in the old tasks
        // For baseline testing, we define regression as an action completely failing the task condition
        let aggregateRegressionRate = 1.0 - aggregateSuccessRate // Simplified approximation for the baseline
        
        let baseline = BenchmarkBaseline.current
        return baseline.isMet(
            successRate: aggregateSuccessRate,
            averageSteps: aggregateAverageSteps,
            recoveryCount: totalRecoveryAttempts / Int(aggregateRuns),
            wrongTargetRate: aggregateWrongTargetRate,
            patchSuccessRate: aggregatePatchSuccessRate,
            regressionRate: aggregateRegressionRate
        )
    }
}
