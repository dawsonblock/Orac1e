import Foundation

public enum PromptTemplateKind: String, Codable, Sendable, Equatable {
    case planning
    case workflowSelection = "workflow-selection"
    case codeRepair = "code-repair"
    case experimentGeneration = "experiment-generation"
    case osAction = "os-action"
    case recoverySelection = "recovery-selection"
}

public struct PromptTemplate: Sendable, Equatable {
    public let kind: PromptTemplateKind
    public let expectedOutput: [String]
    public let evaluationCriteria: [String]
    public let defaultActions: [String]

    public init(
        kind: PromptTemplateKind,
        expectedOutput: [String],
        evaluationCriteria: [String],
        defaultActions: [String]
    ) {
        self.kind = kind
        self.expectedOutput = expectedOutput
        self.evaluationCriteria = evaluationCriteria
        self.defaultActions = defaultActions
    }
}

public struct PromptTemplateRegistry {
    public init() {}

    public func template(for kind: PromptTemplateKind) -> PromptTemplate {
        switch kind {
        case .planning:
            PromptTemplate(
                kind: kind,
                expectedOutput: [
                    "One bounded next action",
                    "Short rationale tied to trusted runtime evidence",
                    "Fallback when the action fails",
                ],
                evaluationCriteria: [
                    "Prefer workflow or stable graph reuse before exploration",
                    "Keep the next action bounded and low-risk",
                    "Respect runtime policy and verified execution",
                ],
                defaultActions: [
                    "use_workflow(id)",
                    "reuse_graph_path(edge_ids)",
                    "reuse_candidate_edge(edge_id)",
                    "bounded_exploration",
                    "stop_and_escalate(reason)",
                ]
            )
        case .workflowSelection:
            PromptTemplate(
                kind: kind,
                expectedOutput: [
                    "Workflow reuse decision",
                    "Best matching workflow or an explicit fallback reason",
                ],
                evaluationCriteria: [
                    "Prefer promoted workflows with high replay success",
                    "Reject workflows that conflict with rejected approaches or risks",
                ],
                defaultActions: [
                    "use_workflow(id)",
                    "reuse_graph_path(edge_ids)",
                    "reuse_candidate_edge(edge_id)",
                    "bounded_exploration",
                ]
            )
        case .codeRepair:
            PromptTemplate(
                kind: kind,
                expectedOutput: [
                    "One bounded engineering action",
                    "Smallest viable patch or inspection surface",
                    "Fallback into bounded experiments if confidence is low",
                ],
                evaluationCriteria: [
                    "Prefer trusted workflow and graph reuse before direct repair",
                    "Use repository intelligence to localize likely root cause",
                    "Keep patch scope small and verifiable",
                ],
                defaultActions: [
                    "inspect_file(path)",
                    "inspect_symbol(symbol)",
                    "query_repository_graph(query)",
                    "query_project_memory(query)",
                    "run_build",
                    "run_tests(scope)",
                    "apply_patch(targets)",
                    "start_experiment(branches)",
                    "stop_and_escalate(reason)",
                ]
            )
        case .experimentGeneration:
            PromptTemplate(
                kind: kind,
                expectedOutput: [
                    "Bounded candidate patch set",
                    "Clear ranking criteria",
                    "Replay target for the winning candidate",
                ],
                evaluationCriteria: [
                    "Generate only bounded candidate families",
                    "Prefer candidates with strong repository evidence",
                    "Rank by pass status, patch size, architecture risk, and runtime cost",
                ],
                defaultActions: [
                    "generate_patch_family(path)",
                    "spawn_worktree(candidate)",
                    "run_build",
                    "run_tests(scope)",
                    "rank_candidate(candidate)",
                    "replay_winner(candidate)",
                    "stop_and_escalate(reason)",
                ]
            )
        case .osAction:
            PromptTemplate(
                kind: kind,
                expectedOutput: [
                    "One verified UI action",
                    "Target metadata and expected postcondition",
                    "Recovery fallback if ambiguity or verification failure occurs",
                ],
                evaluationCriteria: [
                    "Use semantic targeting and fail closed on ambiguity",
                    "Prefer existing trusted workflow and graph knowledge",
                    "Keep the action consistent with runtime policy",
                ],
                defaultActions: [
                    "open_app(name)",
                    "focus_window(name)",
                    "semantic_click(target)",
                    "semantic_type(target,text)",
                    "navigate_browser(url)",
                    "choose_recovery(strategy)",
                    "stop_and_escalate(reason)",
                ]
            )
        case .recoverySelection:
            PromptTemplate(
                kind: kind,
                expectedOutput: [
                    "Ordered recovery strategy list",
                    "Most likely recovery action to prepare next",
                ],
                evaluationCriteria: [
                    "Prefer state-improving recoveries before broad retries",
                    "Respect remembered successful recovery strategies",
                    "Keep recovery bounded and verifiable",
                ],
                defaultActions: [
                    "rerank_target",
                    "refresh_observation",
                    "refocus_application",
                    "dismiss_modal",
                    "rerun_focused_tests",
                    "revert_patch",
                    "refresh_repository_index",
                    "rebuild_dependencies",
                    "stop_and_escalate(reason)",
                ]
            )
        }
    }
}
