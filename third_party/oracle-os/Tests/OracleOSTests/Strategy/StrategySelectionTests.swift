import Foundation
import Testing
@testable import OracleOS

@Suite("Strategy Selection")
struct StrategySelectionTests {

    // MARK: - StrategyKind

    @Test("StrategyKind has all expected cases")
    func strategyKindCases() {
        let kinds: [StrategyKind] = [
            .workflowExecution, .graphNavigation, .repoRepair,
            .diagnosticAnalysis, .browserInteraction, .permissionResolution,
            .recoveryMode, .experimentMode, .directExecution,
        ]
        #expect(kinds.count == 9)
        #expect(StrategyKind.allCases.count == 9)
    }

    // MARK: - OperatorFamily

    @Test("OperatorFamily has all expected cases")
    func operatorFamilyCases() {
        let families: [OperatorFamily] = [
            .workflow, .graphEdge, .browserTargeted, .hostTargeted,
            .repoAnalysis, .patchGeneration, .patchExperiment,
            .recovery, .permissionHandling, .exploration, .llmProposal,
        ]
        #expect(families.count == 11)
        #expect(OperatorFamily.allCases.count == 11)
    }

    // MARK: - SelectedStrategy

    @Test("SelectedStrategy allows checks work correctly")
    func selectedStrategyAllowsChecks() {
        let strategy = SelectedStrategy(
            kind: .repoRepair,
            confidence: 0.8,
            rationale: "test",
            allowedOperatorFamilies: [.repoAnalysis, .patchGeneration, .recovery]
        )
        #expect(strategy.allows(.repoAnalysis))
        #expect(strategy.allows(.patchGeneration))
        #expect(strategy.allows(.recovery))
        #expect(!strategy.allows(.browserTargeted))
        #expect(!strategy.allows(.hostTargeted))
        #expect(!strategy.allows(.workflow))
    }

    // MARK: - StrategyLibrary

    @Test("StrategyLibrary maps all strategy kinds to operator families")
    func strategyLibraryMapsAllKinds() {
        for kind in StrategyKind.allCases {
            let families = StrategyLibrary.allowedFamilies(for: kind)
            #expect(!families.isEmpty, "Strategy \(kind) should have allowed families")
        }
    }

    @Test("repoRepair strategy does not allow browser-targeted operators")
    func repoRepairExcludesBrowser() {
        let families = StrategyLibrary.allowedFamilies(for: .repoRepair)
        #expect(!families.contains(.browserTargeted))
        #expect(families.contains(.repoAnalysis))
        #expect(families.contains(.patchGeneration))
    }

    @Test("browserInteraction strategy does not allow repo-analysis operators")
    func browserExcludesRepo() {
        let families = StrategyLibrary.allowedFamilies(for: .browserInteraction)
        #expect(!families.contains(.repoAnalysis))
        #expect(!families.contains(.patchGeneration))
        #expect(families.contains(.browserTargeted))
    }

    @Test("recoveryMode strategy has bounded operator families")
    func recoveryModeBounded() {
        let families = StrategyLibrary.allowedFamilies(for: .recoveryMode)
        #expect(families.contains(.recovery))
        #expect(families.contains(.graphEdge))
        #expect(!families.contains(.browserTargeted))
        #expect(!families.contains(.repoAnalysis))
    }

    // MARK: - StrategySelector

    @Test("Strategy selector produces SelectedStrategy for modal conditions")
    func strategySelectorRecoveryForModal() {
        let selector = StrategySelector()
        let goal = Goal(description: "submit form", preferredAgentKind: .os)
        let worldState = makeWorldState(app: "Safari", modalClass: "dialog")

        let strategy = selector.selectStrategy(
            goal: goal,
            worldState: worldState,
            memoryInfluence: MemoryInfluence(),
            workflowIndex: WorkflowIndex(),
            agentKind: .os
        )

        #expect(strategy.kind == .recoveryMode)
        #expect(!strategy.allowedOperatorFamilies.isEmpty)
        #expect(strategy.confidence > 0)
    }

    @Test("Strategy selector produces repoRepair for failing tests with repo")
    func strategySelectorRepoRepair() {
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

        let strategy = selector.selectStrategy(
            goal: goal,
            worldState: worldState,
            memoryInfluence: MemoryInfluence(),
            workflowIndex: WorkflowIndex(),
            agentKind: .code
        )

        #expect(strategy.kind == .repoRepair)
        let families = strategy.allowedOperatorFamilies
        #expect(families.contains(.repoAnalysis))
        #expect(families.contains(.patchGeneration))
        #expect(!families.contains(.browserTargeted))
    }

    @Test("Strategy selector produces directExecution for OS agent with no special conditions")
    func strategySelectorDirectExecution() {
        let selector = StrategySelector()
        let goal = Goal(description: "open finder", preferredAgentKind: .os)
        let worldState = makeWorldState(app: "Finder")

        let strategy = selector.selectStrategy(
            goal: goal,
            worldState: worldState,
            memoryInfluence: MemoryInfluence(),
            workflowIndex: WorkflowIndex(),
            agentKind: .os
        )

        #expect(strategy.kind == .directExecution)
    }

    @Test("Strategy selector returns recovery for repeated failures")
    func strategySelectorRecoveryForFailures() {
        let selector = StrategySelector()
        let goal = Goal(description: "do something", preferredAgentKind: .mixed)
        let worldState = makeWorldState(app: "App")

        let strategy = selector.selectStrategy(
            goal: goal,
            worldState: worldState,
            memoryInfluence: MemoryInfluence(),
            workflowIndex: WorkflowIndex(),
            agentKind: .mixed,
            recentFailureCount: 5
        )

        #expect(strategy.kind == .recoveryMode)
    }

    @Test("Selected strategy has non-empty rationale")
    func selectedStrategyHasRationale() {
        let selector = StrategySelector()
        let goal = Goal(description: "test", preferredAgentKind: .os)
        let worldState = makeWorldState(app: "Finder")

        let strategy = selector.selectStrategy(
            goal: goal,
            worldState: worldState,
            memoryInfluence: MemoryInfluence(),
            workflowIndex: WorkflowIndex(),
            agentKind: .os
        )

        #expect(!strategy.rationale.isEmpty)
        #expect(strategy.reevaluateAfterStepCount > 0)
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
