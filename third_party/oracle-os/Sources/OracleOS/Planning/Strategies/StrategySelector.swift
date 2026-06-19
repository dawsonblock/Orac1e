import Foundation

/// Chooses a high-level ``TaskStrategy`` based on the current goal, world state,
/// memory, and workflow availability. The planner then generates plans within
/// the scope of the selected strategy.
///
/// Strategy selection is the **mandatory first decision stage** in every
/// planning cycle. No plan generation happens before a strategy is selected.
public final class StrategySelector: @unchecked Sendable {
    private let library: [TaskStrategy]
    private let llmClient: LLMClient?

    public init(
        library: [TaskStrategy]? = nil,
        llmClient: LLMClient? = nil
    ) {
        self.library = library ?? Self.defaultLibrary()
        self.llmClient = llmClient
    }

    // MARK: - Primary entry point: SelectedStrategy

    /// Select the canonical ``SelectedStrategy`` for the current situation.
    ///
    /// This is the required first decision stage. The returned value constrains
    /// all downstream plan generation via ``SelectedStrategy/allowedOperatorFamilies``.
    public func selectStrategy(
        goal: Goal,
        worldState: WorldState,
        memoryInfluence: MemoryInfluence,
        workflowIndex: WorkflowIndex,
        agentKind: AgentKind,
        recentFailureCount: Int = 0
    ) -> SelectedStrategy {
        let conditions = activeConditions(
            worldState: worldState,
            goal: goal,
            workflowIndex: workflowIndex,
            recentFailureCount: recentFailureCount
        )

        let kind = resolveStrategyKind(
            goal: goal,
            worldState: worldState,
            conditions: conditions,
            agentKind: agentKind,
            memoryInfluence: memoryInfluence,
            workflowIndex: workflowIndex,
            recentFailureCount: recentFailureCount
        )

        let allowed = StrategyLibrary.allowedFamilies(for: kind)
        let confidence = strategyConfidence(
            kind: kind,
            conditions: conditions,
            memoryInfluence: memoryInfluence
        )
        let rationale = buildRationale(
            kind: kind,
            conditions: conditions,
            goal: goal
        )

        return SelectedStrategy(
            kind: kind,
            confidence: confidence,
            rationale: rationale,
            allowedOperatorFamilies: allowed,
            reevaluateAfterStepCount: reevaluateThreshold(for: kind)
        )
    }

    // MARK: - Legacy entry point (preserved for backward compatibility)

    /// Select the best strategy for the current situation.
    public func select(
        goal: Goal,
        worldState: WorldState,
        memoryInfluence: MemoryInfluence,
        workflowIndex: WorkflowIndex,
        agentKind: AgentKind
    ) -> StrategySelection {
        let conditions = activeConditions(
            worldState: worldState,
            goal: goal,
            workflowIndex: workflowIndex
        )

        var scored: [(TaskStrategy, Double)] = []
        for strategy in library {
            guard strategy.applicableAgentKinds.contains(agentKind) else { continue }
            let conditionMatch = conditionScore(
                strategy: strategy,
                activeConditions: conditions
            )
            guard conditionMatch > 0 || strategy.requiredConditions.isEmpty else { continue }

            let memoryBoost = memoryBoost(
                strategy: strategy,
                influence: memoryInfluence
            )
            let total = strategy.priorityScore + conditionMatch + memoryBoost
            scored.append((strategy, total))
        }

        scored.sort { $0.1 > $1.1 }

        guard let best = scored.first else {
            let fallback = TaskStrategy(
                kind: .uiExploration,
                description: "Default exploration when no strategy matches",
                priorityScore: 0.1
            )
            return StrategySelection(
                selected: fallback,
                score: 0.1,
                alternatives: [],
                conditions: conditions,
                notes: ["no strategy matched; falling back to exploration"]
            )
        }

        return StrategySelection(
            selected: best.0,
            score: best.1,
            alternatives: scored.dropFirst().prefix(3).map { $0.0 },
            conditions: conditions,
            notes: []
        )
    }

    // MARK: - Strategy resolution

    private func resolveStrategyKind(
        goal: Goal,
        worldState: WorldState,
        conditions: Set<StrategyCondition>,
        agentKind: AgentKind,
        memoryInfluence: MemoryInfluence,
        workflowIndex: WorkflowIndex,
        recentFailureCount: Int
    ) -> StrategyKind {
        // Priority 1: Repeated recent failures → recovery.
        if conditions.contains(.repeatedFailures) || recentFailureCount >= 3 {
            return .recoveryMode
        }

        // Priority 2: Modal present → recovery.
        if conditions.contains(.modalPresent) {
            return .recoveryMode
        }

        // Priority 3: Strong workflow match → workflow execution.
        let workflows = workflowIndex.matching(goal: goal)
        if !workflows.isEmpty, conditions.contains(.workflowAvailable) {
            return .workflowExecution
        }

        // Priority 4: Repo loaded + tests/build failing → repoRepair.
        if conditions.contains(.repositoryOpen) {
            if conditions.contains(.testsFailing) || conditions.contains(.buildFailing) {
                return .repoRepair
            }
        }

        // Priority 5: Browser page is dominant → browserInteraction.
        if conditions.contains(.browserPageActive) {
            return .browserInteraction
        }

        // Priority 6: Code agent with repo → diagnosticAnalysis or repoRepair.
        if (agentKind == .code || agentKind == .mixed),
           conditions.contains(.repositoryOpen) {
            return .repoRepair
        }

        // Priority 7: OS agent → directExecution or graphNavigation.
        if agentKind == .os {
            return .directExecution
        }

        // Default: graph navigation for mixed tasks.
        return .graphNavigation
    }

    private func strategyConfidence(
        kind: StrategyKind,
        conditions: Set<StrategyCondition>,
        memoryInfluence: MemoryInfluence
    ) -> Double {
        var confidence = 0.5

        switch kind {
        case .recoveryMode where conditions.contains(.repeatedFailures):
            confidence = 0.85
        case .recoveryMode:
            confidence = 0.75
        case .workflowExecution:
            confidence = 0.8
        case .repoRepair where conditions.contains(.testsFailing):
            confidence = 0.7
        case .repoRepair:
            confidence = 0.6
        case .permissionResolution:
            confidence = 0.9
        case .browserInteraction:
            confidence = 0.6
        default:
            break
        }

        // Memory boost.
        if memoryInfluence.preferredFixPath != nil { confidence += 0.05 }
        if memoryInfluence.executionRankingBias > 0 { confidence += 0.05 }

        return min(confidence, 1.0)
    }

    private func buildRationale(
        kind: StrategyKind,
        conditions: Set<StrategyCondition>,
        goal: Goal
    ) -> String {
        let conditionNames = conditions.map(\.rawValue).sorted().joined(separator: ", ")
        return "selected \(kind.rawValue) given conditions [\(conditionNames)] for goal: \(goal.description.prefix(80))"
    }

    private func reevaluateThreshold(for kind: StrategyKind) -> Int {
        switch kind {
        case .recoveryMode: return 3
        case .workflowExecution: return 8
        case .experimentMode: return 4
        default: return 5
        }
    }

    // MARK: - Condition detection

    private func activeConditions(
        worldState: WorldState,
        goal: Goal,
        workflowIndex: WorkflowIndex,
        recentFailureCount: Int = 0
    ) -> Set<StrategyCondition> {
        var conditions = Set<StrategyCondition>()

        if worldState.repositorySnapshot != nil {
            conditions.insert(.repositoryOpen)
        }
        if worldState.repositorySnapshot?.isGitDirty == true {
            conditions.insert(.gitDirty)
        }
        if worldState.planningState.modalClass != nil {
            conditions.insert(.modalPresent)
        }

        let goalLower = goal.description.lowercased()
        if goalLower.contains("test") || goalLower.contains("failing") {
            conditions.insert(.testsFailing)
        }
        if goalLower.contains("build") || goalLower.contains("compile") {
            conditions.insert(.buildFailing)
        }

        let workflows = workflowIndex.matching(goal: goal)
        if !workflows.isEmpty {
            conditions.insert(.workflowAvailable)
        }

        // Browser detection.
        let app = worldState.observation.app?.lowercased() ?? ""
        if app.contains("chrome") || app.contains("safari") || app.contains("firefox") || app.contains("browser") {
            conditions.insert(.browserPageActive)
        }

        // Repeated failure detection.
        if recentFailureCount >= 3 {
            conditions.insert(.repeatedFailures)
        }

        return conditions
    }

    private func conditionScore(
        strategy: TaskStrategy,
        activeConditions: Set<StrategyCondition>
    ) -> Double {
        guard !strategy.requiredConditions.isEmpty else { return 0.1 }
        let matched = strategy.requiredConditions.filter { activeConditions.contains($0) }
        return Double(matched.count) / Double(strategy.requiredConditions.count)
    }

    private func memoryBoost(
        strategy: TaskStrategy,
        influence: MemoryInfluence
    ) -> Double {
        var boost = 0.0
        if strategy.kind == .codeRepair && influence.preferredFixPath != nil {
            boost += 0.15
        }
        if strategy.kind == .recovery && influence.preferredRecoveryStrategy != nil {
            boost += 0.1
        }
        if strategy.kind == .workflowReuse && influence.executionRankingBias > 0 {
            boost += 0.1
        }
        return boost
    }

    private static func defaultLibrary() -> [TaskStrategy] {
        [
            TaskStrategy(
                kind: .workflowReuse,
                description: "Reuse a validated workflow for the current goal",
                requiredConditions: [.workflowAvailable],
                priorityScore: 0.8,
                notes: ["Highest priority when a matching promoted workflow exists"]
            ),
            TaskStrategy(
                kind: .codeRepair,
                description: "Repair failing code using fault localization and patching",
                applicableAgentKinds: [.code, .mixed],
                requiredConditions: [.repositoryOpen],
                priorityScore: 0.7
            ),
            TaskStrategy(
                kind: .testFix,
                description: "Fix failing tests by analyzing stack traces and applying targeted patches",
                applicableAgentKinds: [.code, .mixed],
                requiredConditions: [.repositoryOpen, .testsFailing],
                priorityScore: 0.75
            ),
            TaskStrategy(
                kind: .buildFix,
                description: "Fix build failures by analyzing compiler errors",
                applicableAgentKinds: [.code, .mixed],
                requiredConditions: [.repositoryOpen, .buildFailing],
                priorityScore: 0.75
            ),
            TaskStrategy(
                kind: .dependencyRepair,
                description: "Repair dependency issues in the project",
                applicableAgentKinds: [.code, .mixed],
                requiredConditions: [.repositoryOpen],
                priorityScore: 0.6
            ),
            TaskStrategy(
                kind: .recovery,
                description: "Recover from blocking conditions (modals, wrong focus)",
                requiredConditions: [.modalPresent],
                priorityScore: 0.9,
                notes: ["Highest urgency — must resolve before other strategies"]
            ),
            TaskStrategy(
                kind: .navigation,
                description: "Navigate to a target application or page",
                applicableAgentKinds: [.os, .mixed],
                priorityScore: 0.5
            ),
            TaskStrategy(
                kind: .uiExploration,
                description: "Explore the UI to discover available actions",
                applicableAgentKinds: [.os, .mixed],
                priorityScore: 0.3,
                notes: ["Lowest priority — used when other strategies don't apply"]
            ),
            TaskStrategy(
                kind: .configurationDiagnosis,
                description: "Diagnose system or environment configuration issues",
                priorityScore: 0.4
            ),
        ]
    }
}

/// The result of strategy selection including the chosen strategy and metadata.
public struct StrategySelection: Sendable {
    public let selected: TaskStrategy
    public let score: Double
    public let alternatives: [TaskStrategy]
    public let conditions: Set<StrategyCondition>
    public let notes: [String]

    public init(
        selected: TaskStrategy,
        score: Double,
        alternatives: [TaskStrategy] = [],
        conditions: Set<StrategyCondition> = [],
        notes: [String] = []
    ) {
        self.selected = selected
        self.score = score
        self.alternatives = alternatives
        self.conditions = conditions
        self.notes = notes
    }
}
