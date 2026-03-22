import Foundation

/// Top-level strategy enum defining the agent's high-level approach.
///
/// Strategy selection is the first decision stage in every planning cycle.
/// No plan generation happens before a strategy is selected.
public enum StrategyKind: String, Sendable, Codable, CaseIterable {
    case workflowExecution = "workflow_execution"
    case graphNavigation = "graph_navigation"
    case repoRepair = "repo_repair"
    case diagnosticAnalysis = "diagnostic_analysis"
    case browserInteraction = "browser_interaction"
    case permissionResolution = "permission_resolution"
    case recoveryMode = "recovery_mode"
    case experimentMode = "experiment_mode"
    case directExecution = "direct_execution"
}
