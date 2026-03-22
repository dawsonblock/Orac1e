import Foundation

/// A high-level approach the agent can adopt for a task. The strategy layer
/// sits above the planner and constrains which planning operators are considered.
///
///     goal → strategy selection → planning → execution
///
/// By selecting a strategy first, the planner avoids mixing unrelated operators
/// and produces more focused plans.
public struct TaskStrategy: Sendable {
    public let kind: TaskStrategyKind
    public let description: String
    public let applicableAgentKinds: [AgentKind]
    public let requiredConditions: [StrategyCondition]
    public let priorityScore: Double
    public let notes: [String]

    public init(
        kind: TaskStrategyKind,
        description: String,
        applicableAgentKinds: [AgentKind] = AgentKind.allCases,
        requiredConditions: [StrategyCondition] = [],
        priorityScore: Double = 0.5,
        notes: [String] = []
    ) {
        self.kind = kind
        self.description = description
        self.applicableAgentKinds = applicableAgentKinds
        self.requiredConditions = requiredConditions
        self.priorityScore = priorityScore
        self.notes = notes
    }
}

public enum TaskStrategyKind: String, Sendable, CaseIterable {
    case workflowReuse = "workflow_reuse"
    case codeRepair = "code_repair"
    case uiExploration = "ui_exploration"
    case configurationDiagnosis = "configuration_diagnosis"
    case dependencyRepair = "dependency_repair"
    case buildFix = "build_fix"
    case testFix = "test_fix"
    case navigation = "navigation"
    case recovery = "recovery"

    /// Map legacy ``TaskStrategyKind`` to the canonical ``StrategyKind``.
    public var strategyKind: StrategyKind {
        switch self {
        case .workflowReuse: return .workflowExecution
        case .codeRepair: return .repoRepair
        case .uiExploration: return .browserInteraction
        case .configurationDiagnosis: return .diagnosticAnalysis
        case .dependencyRepair: return .repoRepair
        case .buildFix: return .repoRepair
        case .testFix: return .repoRepair
        case .navigation: return .graphNavigation
        case .recovery: return .recoveryMode
        }
    }
}

public enum StrategyCondition: String, Sendable {
    case repositoryOpen = "repository_open"
    case buildFailing = "build_failing"
    case testsFailing = "tests_failing"
    case modalPresent = "modal_present"
    case wrongApplication = "wrong_application"
    case workflowAvailable = "workflow_available"
    case gitDirty = "git_dirty"
    case patchApplied = "patch_applied"
    case browserPageActive = "browser_page_active"
    case repeatedFailures = "repeated_failures"
    case permissionDialogActive = "permission_dialog_active"
}

// MARK: - Strategy ↔ Operator Family mapping

/// Maps each ``StrategyKind`` to its allowed ``OperatorFamily`` set.
///
/// This is the key control constraint: plan generation and graph expansion
/// only consider operator families that the current strategy allows.
public enum StrategyLibrary {
    public static func allowedFamilies(for kind: StrategyKind) -> [OperatorFamily] {
        switch kind {
        case .workflowExecution:
            return [.workflow, .graphEdge, .recovery]
        case .repoRepair:
            return [.repoAnalysis, .patchGeneration, .patchExperiment, .llmProposal, .recovery]
        case .browserInteraction:
            return [.browserTargeted, .llmProposal, .recovery]
        case .permissionResolution:
            return [.permissionHandling, .hostTargeted, .recovery]
        case .recoveryMode:
            return [.recovery, .graphEdge]
        case .experimentMode:
            return [.patchExperiment, .repoAnalysis, .recovery]
        case .graphNavigation:
            return [.graphEdge, .workflow, .recovery]
        case .diagnosticAnalysis:
            return [.repoAnalysis, .llmProposal]
        case .directExecution:
            return [.hostTargeted, .browserTargeted, .graphEdge]
        }
    }
}
