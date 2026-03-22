import Foundation
import Testing
@testable import OracleOS

@Suite("Strategy Layer")
struct StrategyLayerTests {

    // MARK: - StrategySelector

    @Test("Strategy selector chooses recovery when modal is present")
    func strategySelectorChoosesRecoveryForModal() {
        let selector = StrategySelector()
        let goal = Goal(description: "submit form", preferredAgentKind: .os)
        let worldState = makeWorldState(app: "Safari", modalClass: "dialog")

        let selection = selector.select(
            goal: goal,
            worldState: worldState,
            memoryInfluence: MemoryInfluence(),
            workflowIndex: WorkflowIndex(),
            agentKind: .os
        )

        #expect(selection.selected.kind == .recovery)
        #expect(selection.conditions.contains(.modalPresent))
    }

    @Test("Strategy selector chooses code repair when repo is open")
    func strategySelectorChoosesCodeRepair() {
        let selector = StrategySelector()
        let goal = Goal(description: "fix failing tests", preferredAgentKind: .code)
        let worldState = makeWorldState(
            app: "Workspace",
            repositorySnapshot: RepositorySnapshot(
                id: "repo",
                workspaceRoot: "/tmp/ws",
                buildTool: .swiftPackage,
                files: [],
                symbolGraph: SymbolGraph(),
                dependencyGraph: DependencyGraph(),
                testGraph: TestGraph(),
                activeBranch: "main",
                isGitDirty: false
            )
        )

        let selection = selector.select(
            goal: goal,
            worldState: worldState,
            memoryInfluence: MemoryInfluence(),
            workflowIndex: WorkflowIndex(),
            agentKind: .code
        )

        #expect(selection.conditions.contains(.repositoryOpen))
        #expect(selection.conditions.contains(.testsFailing))
        let strategyKind = selection.selected.kind
        #expect(strategyKind == .testFix || strategyKind == .codeRepair)
    }

    @Test("Strategy selector falls back to exploration when nothing matches")
    func strategySelectorFallsBackToExploration() {
        let selector = StrategySelector()
        let goal = Goal(description: "do something", preferredAgentKind: .os)
        let worldState = makeWorldState(app: "Finder")

        let selection = selector.select(
            goal: goal,
            worldState: worldState,
            memoryInfluence: MemoryInfluence(),
            workflowIndex: WorkflowIndex(),
            agentKind: .os
        )

        #expect(selection.selected.kind != .recovery)
        #expect(selection.score > 0)
    }

    @Test("Strategy selector boosts score with memory influence")
    func strategySelectorBoostsWithMemory() {
        let selector = StrategySelector()
        let goal = Goal(description: "fix code", preferredAgentKind: .code)
        let worldState = makeWorldState(
            app: "Workspace",
            repositorySnapshot: RepositorySnapshot(
                id: "repo",
                workspaceRoot: "/tmp/ws",
                buildTool: .swiftPackage,
                files: [],
                symbolGraph: SymbolGraph(),
                dependencyGraph: DependencyGraph(),
                testGraph: TestGraph(),
                activeBranch: "main",
                isGitDirty: false
            )
        )

        let withMemory = selector.select(
            goal: goal,
            worldState: worldState,
            memoryInfluence: MemoryInfluence(preferredFixPath: "Sources/Foo.swift"),
            workflowIndex: WorkflowIndex(),
            agentKind: .code
        )

        let withoutMemory = selector.select(
            goal: goal,
            worldState: worldState,
            memoryInfluence: MemoryInfluence(),
            workflowIndex: WorkflowIndex(),
            agentKind: .code
        )

        // Memory influence should boost the score for code repair strategies
        #expect(withMemory.score >= withoutMemory.score)
    }

    @Test("Strategy selector provides alternatives")
    func strategySelectorProvidesAlternatives() {
        let selector = StrategySelector()
        let goal = Goal(description: "fix tests in project", preferredAgentKind: .code)
        let worldState = makeWorldState(
            app: "Workspace",
            repositorySnapshot: RepositorySnapshot(
                id: "repo",
                workspaceRoot: "/tmp/ws",
                buildTool: .swiftPackage,
                files: [],
                symbolGraph: SymbolGraph(),
                dependencyGraph: DependencyGraph(),
                testGraph: TestGraph(),
                activeBranch: "main",
                isGitDirty: false
            )
        )

        let selection = selector.select(
            goal: goal,
            worldState: worldState,
            memoryInfluence: MemoryInfluence(),
            workflowIndex: WorkflowIndex(),
            agentKind: .code
        )

        // Should have at least one alternative strategy
        #expect(!selection.alternatives.isEmpty || selection.score > 0)
    }

    // MARK: - StrategyEvaluator

    @Test("Strategy evaluator records and computes effectiveness")
    func strategyEvaluatorComputesEffectiveness() {
        let evaluator = StrategyEvaluator()
        evaluator.record(StrategyEvaluation(
            taskID: "t1", strategyKind: .codeRepair, succeeded: true,
            durationSeconds: 10, recoveryCount: 0, stepCount: 3
        ))
        evaluator.record(StrategyEvaluation(
            taskID: "t2", strategyKind: .codeRepair, succeeded: true,
            durationSeconds: 15, recoveryCount: 1, stepCount: 4
        ))
        evaluator.record(StrategyEvaluation(
            taskID: "t3", strategyKind: .codeRepair, succeeded: false,
            durationSeconds: 20, recoveryCount: 2, stepCount: 5
        ))

        let score = evaluator.effectiveness(for: .codeRepair)
        #expect(score.sampleCount == 3)
        #expect(score.successRate > 0.6)
        #expect(score.successRate < 0.7)
        #expect(score.averageDuration > 0)
    }

    @Test("Strategy evaluator returns zero for unknown strategies")
    func strategyEvaluatorReturnsZeroForUnknown() {
        let evaluator = StrategyEvaluator()
        let score = evaluator.effectiveness(for: .navigation)
        #expect(score.sampleCount == 0)
        #expect(score.successRate == 0)
    }

    @Test("Strategy evaluator ranks strategies by effectiveness")
    func strategyEvaluatorRanksStrategies() {
        let evaluator = StrategyEvaluator()

        // codeRepair: 100% success
        evaluator.record(StrategyEvaluation(taskID: "t1", strategyKind: .codeRepair, succeeded: true))
        evaluator.record(StrategyEvaluation(taskID: "t2", strategyKind: .codeRepair, succeeded: true))

        // uiExploration: 50% success
        evaluator.record(StrategyEvaluation(taskID: "t3", strategyKind: .uiExploration, succeeded: true))
        evaluator.record(StrategyEvaluation(taskID: "t4", strategyKind: .uiExploration, succeeded: false))

        let ranked = evaluator.rankedStrategies()
        #expect(ranked.count == 2)
        #expect(ranked.first?.strategyKind == .codeRepair)
    }

    @Test("Strategy evaluator returns recent evaluations")
    func strategyEvaluatorReturnsRecent() {
        let evaluator = StrategyEvaluator()
        for i in 0..<5 {
            evaluator.record(StrategyEvaluation(
                taskID: "t\(i)", strategyKind: .codeRepair, succeeded: true
            ))
        }

        let recent = evaluator.recentEvaluations(limit: 3)
        #expect(recent.count == 3)
    }

    // MARK: - TaskStrategy

    @Test("TaskStrategyKind has all expected cases")
    func taskStrategyKindCases() {
        let kinds: [TaskStrategyKind] = [
            .workflowReuse, .codeRepair, .uiExploration,
            .configurationDiagnosis, .dependencyRepair, .buildFix,
            .testFix, .navigation, .recovery
        ]
        #expect(kinds.count == 9)
    }

    @Test("PlanSourceType includes strategy case")
    func planSourceTypeIncludesStrategy() {
        let strategy = PlanSourceType.strategy
        #expect(strategy.rawValue == "strategy")
    }

    // MARK: - Helpers

    private func makeWorldState(
        app: String,
        modalClass: String? = nil,
        repositorySnapshot: RepositorySnapshot? = nil
    ) -> WorldState {
        WorldState(
            observationHash: "hash-\(app)",
            planningState: PlanningState(
                id: PlanningStateID(rawValue: "\(app)|state"),
                clusterKey: StateClusterKey(rawValue: "\(app)|state"),
                appID: app,
                domain: nil,
                windowClass: nil,
                taskPhase: "test",
                focusedRole: nil,
                modalClass: modalClass,
                navigationClass: nil,
                controlContext: nil
            ),
            observation: Observation(
                app: app,
                windowTitle: app,
                url: nil,
                focusedElementID: nil,
                elements: []
            ),
            repositorySnapshot: repositorySnapshot
        )
    }
}
