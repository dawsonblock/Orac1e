// EvalBaseline.swift — Baseline metrics for regression detection.
//
// Each entry captures the expected performance of a benchmark task.
// The eval harness compares current metrics against these baselines
// to detect regressions before merging.

import Foundation
@testable import OracleOS

/// Known baselines keyed by task family and task name.
enum EvalBaseline {

    /// Baseline metrics for each benchmark task.
    ///
    /// These values should be updated when a genuine improvement is verified
    /// and accepted. Do not inflate baselines to suppress regressions.
    static let baselines: [String: EvalMetrics] = [

        // -- Operator tasks --
        "operator/finder-rename": EvalMetrics(
            successRate: 1.0,
            firstPassSuccessRate: 1.0,
            averageSteps: 3,
            recoverySuccessRate: 0,
            graphReuseRatio: 0,
            workflowReuseRatio: 0,
            ambiguityFailureCount: 0,
            patchSelectionSuccessRate: 0,
            wrongTargetRate: 0
        ),

        "operator/chrome-navigation": EvalMetrics(
            successRate: 1.0,
            firstPassSuccessRate: 1.0,
            averageSteps: 2,
            recoverySuccessRate: 0,
            graphReuseRatio: 1.0,
            workflowReuseRatio: 0,
            ambiguityFailureCount: 0,
            patchSelectionSuccessRate: 0,
            wrongTargetRate: 0
        ),

        "operator/gmail-compose": EvalMetrics(
            successRate: 1.0,
            firstPassSuccessRate: 1.0,
            averageSteps: 3,
            recoverySuccessRate: 0,
            graphReuseRatio: 0,
            workflowReuseRatio: 1.0,
            ambiguityFailureCount: 0,
            patchSelectionSuccessRate: 0,
            wrongTargetRate: 0
        ),

        "operator/os-recovery": EvalMetrics(
            successRate: 1.0,
            firstPassSuccessRate: 0,
            averageSteps: 4,
            recoverySuccessRate: 1.0,
            graphReuseRatio: 0,
            workflowReuseRatio: 0,
            ambiguityFailureCount: 0,
            patchSelectionSuccessRate: 0,
            wrongTargetRate: 0
        ),

        // -- Coding tasks --
        "coding/build-break-repair": EvalMetrics(
            successRate: 1.0,
            firstPassSuccessRate: 1.0,
            averageSteps: 3,
            recoverySuccessRate: 0,
            graphReuseRatio: 0,
            workflowReuseRatio: 0,
            ambiguityFailureCount: 0,
            patchSelectionSuccessRate: 1.0,
            wrongTargetRate: 0
        ),

        "coding/failing-test-repair": EvalMetrics(
            successRate: 1.0,
            firstPassSuccessRate: 1.0,
            averageSteps: 4,
            recoverySuccessRate: 0,
            graphReuseRatio: 0,
            workflowReuseRatio: 0,
            ambiguityFailureCount: 0,
            patchSelectionSuccessRate: 1.0,
            wrongTargetRate: 0
        ),
    ]

    /// Look up the baseline for a given report, or return nil if none exists.
    static func baseline(for report: EvalReport) -> EvalMetrics? {
        let key = "\(report.family.rawValue)/\(report.taskName)"
        return baselines[key]
    }
}
