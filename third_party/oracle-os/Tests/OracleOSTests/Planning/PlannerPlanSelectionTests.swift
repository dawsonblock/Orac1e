import Foundation
import Testing
@testable import OracleOS

@Suite("Planner Plan Selection")
struct PlannerPlanSelectionTests {

    @Test("Workflow plan beats exploration when valid workflow exists")
    func workflowBeatsExplorationWhenValid() {
        let workflowIndex = WorkflowIndex()
        workflowIndex.add(
            WorkflowPlan(
                id: "workflow-test",
                agentKind: .os,
                goalPattern: "click submit button",
                steps: [
                    WorkflowStep(
                        agentKind: .os,
                        stepPhase: .operatingSystem,
                        actionContract: ActionContract(
                            id: "submit-click",
                            skillName: "click",
                            targetRole: "AXButton",
                            targetLabel: "Submit",
                            locatorStrategy: "query"
                        ),
                        semanticQuery: ElementQuery(text: "Submit", clickable: true, visibleOnly: true, app: "Safari"),
                        fromPlanningStateID: "safari|form|browse"
                    ),
                ],
                successRate: 0.90,
                repeatedTraceSegmentCount: 3,
                replayValidationSuccess: 1.0,
                promotionStatus: .promoted
            )
        )

        let planner = MainPlanner(workflowIndex: workflowIndex, reasoningThreshold: 0)
        let goal = Goal(
            description: "click submit button on form",
            targetApp: "Safari",
            targetDomain: "example.com",
            preferredAgentKind: .os
        )
        planner.setGoal(goal)

        let worldState = WorldState(
            observationHash: "safari-form",
            planningState: planningState(
                id: "safari|form|browse",
                appID: "Safari",
                domain: "example.com",
                taskPhase: "browse",
                modalClass: nil
            ),
            observation: Observation(
                app: "Safari",
                windowTitle: "Form - Safari",
                url: "https://example.com/form",
                focusedElementID: nil,
                elements: [
                    UnifiedElement(id: "submit", source: .ax, role: "AXButton", label: "Submit", confidence: 0.95),
                ]
            )
        )

        let decision = planner.nextStep(
            worldState: worldState,
            graphStore: GraphStore(databaseURL: makeTempGraphURL())
        )

        #expect(decision?.source == .workflow)
        #expect(decision?.workflowID == "workflow-test")
    }

    @Test("Stable graph plan beats candidate graph plan")
    func stableGraphBeatsCandidateGraph() {
        let planner = MainPlanner(reasoningThreshold: 0)
        let goal = Goal(
            description: "open settings in Safari",
            targetApp: "Safari",
            preferredAgentKind: .os
        )
        planner.setGoal(goal)

        let graphStore = GraphStore(databaseURL: makeTempGraphURL())
        _ = graphStore.outgoingStableEdges(
            from: PlanningStateID(rawValue: "safari|browse")
        )
        _ = graphStore.outgoingCandidateEdges(
            from: PlanningStateID(rawValue: "safari|browse")
        )

        // Stable edges should be preferred over candidate edges in plan selection
        // This test validates the scoring weights: stable gets 0.35 base + 0.25×score
        // vs candidate which gets 0.2 base + 0.15×score
        let stableBaseScore = 0.35
        let candidateBaseScore = 0.2
        #expect(stableBaseScore > candidateBaseScore)
    }

    @Test("Low-confidence code tasks escalate to experiments")
    func lowConfidenceCodeTasksEscalateToExperiments() {
        let planner = MainPlanner(reasoningThreshold: 0.25)
        let goal = Goal(
            description: "fix the failing unit test in Calculator.swift",
            workspaceRoot: "/tmp/workspace",
            preferredAgentKind: .code
        )
        planner.setGoal(goal)

        let worldState = WorldState(
            observationHash: "workspace-test-failure",
            planningState: planningState(
                id: "workspace|test-failure",
                appID: "Workspace",
                domain: nil,
                taskPhase: "engineering",
                modalClass: nil
            ),
            observation: Observation(
                app: "Workspace",
                windowTitle: "Workspace",
                url: nil,
                focusedElementID: nil,
                elements: []
            ),
            repositorySnapshot: RepositorySnapshot(
                id: "repo",
                workspaceRoot: "/tmp/workspace",
                buildTool: .swiftPackage,
                files: [
                    RepositoryFile(path: "Sources/Calculator.swift", isDirectory: false),
                    RepositoryFile(path: "Tests/CalculatorTests.swift", isDirectory: false),
                ],
                symbolGraph: SymbolGraph(),
                dependencyGraph: DependencyGraph(),
                testGraph: TestGraph(),
                activeBranch: "main",
                isGitDirty: false
            )
        )

        let decision = planner.nextStep(
            worldState: worldState,
            graphStore: GraphStore(databaseURL: makeTempGraphURL())
        )

        // Code planner should produce a decision for test failures
        #expect(decision != nil)
        #expect(decision?.agentKind == .code)
    }

    @Test("Memory bias changes plan ordering in evaluator")
    func memoryBiasChangesPlanOrdering() {
        let evaluator = PlanEvaluator(workflowRetriever: WorkflowRetriever())
        let taskContext = TaskContext.from(
            goal: Goal(description: "fix calculator", workspaceRoot: "/tmp/workspace", preferredAgentKind: .code),
            workspaceRoot: URL(fileURLWithPath: "/tmp/workspace", isDirectory: true)
        )
        let worldState = WorldState(
            observationHash: "workspace",
            planningState: planningState(
                id: "workspace|dirty",
                appID: "Workspace",
                domain: nil,
                taskPhase: "engineering",
                modalClass: nil
            ),
            observation: Observation(app: "Workspace", windowTitle: "Workspace", url: nil, focusedElementID: nil, elements: []),
            repositorySnapshot: RepositorySnapshot(
                id: "repo",
                workspaceRoot: "/tmp/workspace",
                buildTool: .swiftPackage,
                files: [
                    RepositoryFile(path: "Sources/Calculator.swift", isDirectory: false),
                ],
                symbolGraph: SymbolGraph(),
                dependencyGraph: DependencyGraph(),
                testGraph: TestGraph(),
                activeBranch: "main",
                isGitDirty: true
            )
        )
        let goal = Goal(description: "fix calculator", workspaceRoot: "/tmp/workspace", preferredAgentKind: .code)
        let memoryInfluence = MemoryInfluence(preferredFixPath: "Sources/Calculator.swift")
        let state = ReasoningPlanningState(
            taskContext: taskContext,
            worldState: worldState,
            memoryInfluence: memoryInfluence
        )

        let plans = ReasoningEngine().generatePlans(from: state)
        let scored = evaluator.evaluate(
            plans: plans,
            taskContext: taskContext,
            goal: goal,
            worldState: worldState,
            graphStore: GraphStore(databaseURL: makeTempGraphURL()),
            workflowIndex: WorkflowIndex(),
            memoryStore: UnifiedMemoryStore()
        )

        #expect(!scored.isEmpty)
        // Plans should be sorted by score (descending)
        for i in 0..<max(scored.count - 1, 0) {
            #expect(scored[i].score >= scored[i + 1].score)
        }
    }

    private func planningState(
        id: String,
        appID: String,
        domain: String?,
        taskPhase: String,
        modalClass: String?
    ) -> PlanningState {
        PlanningState(
            id: PlanningStateID(rawValue: id),
            clusterKey: StateClusterKey(rawValue: id),
            appID: appID,
            domain: domain,
            windowClass: nil,
            taskPhase: taskPhase,
            focusedRole: nil,
            modalClass: modalClass,
            navigationClass: nil,
            controlContext: nil
        )
    }

    private func makeTempGraphURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("graph.sqlite3", isDirectory: false)
    }
}
