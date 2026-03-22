import Foundation

/// Categorizes operators into families that strategies can allow or deny.
///
/// Each ``StrategyKind`` maps to a bounded set of allowed operator families
/// via ``StrategyLibrary``. Plan generation and graph expansion filter
/// candidates against this set, preventing cross-strategy noise.
public enum OperatorFamily: String, Sendable, Codable, CaseIterable {
    case workflow
    case graphEdge = "graph_edge"
    case browserTargeted = "browser_targeted"
    case hostTargeted = "host_targeted"
    case repoAnalysis = "repo_analysis"
    case patchGeneration = "patch_generation"
    case patchExperiment = "patch_experiment"
    case recovery
    case permissionHandling = "permission_handling"
    case exploration
    case llmProposal = "llm_proposal"
}

// MARK: - Operator → OperatorFamily mapping

extension ReasoningOperatorKind {
    /// The operator family this reasoning operator belongs to.
    public var operatorFamily: OperatorFamily {
        switch self {
        case .runTests, .buildProject:
            return .repoAnalysis
        case .applyPatch, .revertPatch, .rollbackPatch:
            return .patchGeneration
        case .rerunTests:
            return .repoAnalysis
        case .dismissModal:
            return .recovery
        case .clickTarget:
            return .browserTargeted
        case .openApplication, .focusWindow, .restartApplication:
            return .hostTargeted
        case .navigateBrowser:
            return .browserTargeted
        case .retryWithAlternateTarget:
            return .recovery
        }
    }
}

// MARK: - Workflow → StrategyKind inference

extension StrategyKind {
    /// Infer the strategy kind for a workflow based on its step skill names.
    ///
    /// Shared utility used by ``WorkflowMatcher`` and ``WorkflowRetriever``
    /// to classify workflows by strategy scope.
    public static func infer(fromSkills skills: [String]) -> StrategyKind {
        let hasTestOrBuild = skills.contains { $0.contains("test") || $0.contains("build") }
        let hasPatch = skills.contains { $0.contains("patch") }
        let hasBrowser = skills.contains { $0.contains("browser") || $0.contains("navigate") || $0.contains("click") }

        if hasTestOrBuild && hasPatch { return .repoRepair }
        if hasTestOrBuild { return .repoRepair }
        if hasBrowser { return .browserInteraction }
        return .graphNavigation
    }
}
