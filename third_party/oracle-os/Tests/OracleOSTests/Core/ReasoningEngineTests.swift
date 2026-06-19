import Foundation
import Testing
@testable import OracleOS

@Suite("Reasoning Engine")
struct ReasoningEngineTests {

    @Test("Reasoning engine generates bounded candidate plans")
    func reasoningEngineGeneratesBoundedPlans() {
        let taskContext = TaskContext.from(
            goal: Goal(
                description: "run tests and fix the calculator build failure",
                workspaceRoot: "/tmp/workspace",
                preferredAgentKind: .code
            ),
            workspaceRoot: URL(fileURLWithPath: "/tmp/workspace", isDirectory: true)
        )
        let worldState = WorldState(
            observationHash: "workspace-state",
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
                    RepositoryFile(path: "Sources/Example/Calculator.swift", isDirectory: false),
                    RepositoryFile(path: "Tests/ExampleTests/CalculatorTests.swift", isDirectory: false),
                ],
                symbolGraph: SymbolGraph(),
                dependencyGraph: DependencyGraph(),
                testGraph: TestGraph(),
                activeBranch: "main",
                isGitDirty: true
            )
        )
        let state = ReasoningPlanningState(
            taskContext: taskContext,
            worldState: worldState,
            memoryInfluence: MemoryInfluence(preferredFixPath: "Sources/Example/Calculator.swift")
        )

        let plans = ReasoningEngine().generatePlans(from: state)

        #expect(!plans.isEmpty)
        #expect(plans.count <= 5)
        #expect(plans.allSatisfy { !$0.operators.isEmpty && $0.operators.count <= 3 })
    }

    @Test("Planner uses reasoning to dismiss modal before exploration")
    func plannerUsesReasoningToDismissModal() {
        let planner = MainPlanner(reasoningThreshold: 0.25)
        let goal = Goal(
            description: "dismiss the blocking modal in Safari",
            targetApp: "Safari",
            preferredAgentKind: .os
        )
        planner.setGoal(goal)

        let worldState = WorldState(
            observationHash: "safari-modal",
            planningState: planningState(
                id: "safari|dialog",
                appID: "Safari",
                domain: nil,
                taskPhase: "browse",
                modalClass: "dialog"
            ),
            observation: Observation(
                app: "Safari",
                windowTitle: "Safari",
                url: "https://example.com",
                focusedElementID: nil,
                elements: [
                    UnifiedElement(id: "dialog", source: .ax, role: "AXDialog", label: "Permission dialog", confidence: 0.9),
                    UnifiedElement(id: "close", source: .ax, role: "AXButton", label: "Close", confidence: 0.9),
                ]
            )
        )

        let decision = planner.nextStep(
            worldState: worldState,
            graphStore: GraphStore(databaseURL: makeTempGraphURL())
        )

        #expect(decision?.skillName == "press")
        #expect(decision?.source == .reasoning)
        #expect(decision?.planDiagnostics?.selectedOperatorNames.first == "dismiss_modal")
        #expect(decision?.promptDiagnostics?.templateKind == .planning)
    }

    @Test("Planner preserves workflow fallback when trusted workflow exists")
    func plannerPreservesWorkflowFallback() {
        let workflowIndex = WorkflowIndex()
        workflowIndex.add(
            WorkflowPlan(
                id: "workflow-compose",
                agentKind: .os,
                goalPattern: "open compose",
                steps: [
                    WorkflowStep(
                        agentKind: .os,
                        stepPhase: .operatingSystem,
                        actionContract: ActionContract(
                            id: "compose-click",
                            skillName: "click",
                            targetRole: "AXButton",
                            targetLabel: "Compose",
                            locatorStrategy: "query"
                        ),
                        semanticQuery: ElementQuery(text: "Compose", clickable: true, visibleOnly: true, app: "Google Chrome"),
                        fromPlanningStateID: "chrome|gmail|browse"
                    ),
                ],
                successRate: 0.95,
                repeatedTraceSegmentCount: 4,
                replayValidationSuccess: 1.0,
                promotionStatus: .promoted
            )
        )
        let planner = MainPlanner(workflowIndex: workflowIndex, reasoningThreshold: 0)
        let goal = Goal(
            description: "open compose in gmail",
            targetApp: "Google Chrome",
            targetDomain: "mail.google.com",
            targetTaskPhase: "compose",
            preferredAgentKind: .os
        )
        planner.setGoal(goal)

        let worldState = WorldState(
            observationHash: "gmail-browse",
            planningState: planningState(
                id: "chrome|gmail|browse",
                appID: "Google Chrome",
                domain: "mail.google.com",
                taskPhase: "browse",
                modalClass: nil
            ),
            observation: Observation(
                app: "Google Chrome",
                windowTitle: "Inbox - Gmail",
                url: "https://mail.google.com/mail/u/0/#inbox",
                focusedElementID: nil,
                elements: [
                    UnifiedElement(id: "compose", source: .ax, role: "AXButton", label: "Compose", confidence: 0.95),
                ]
            )
        )

        let decision = planner.nextStep(
            worldState: worldState,
            graphStore: GraphStore(databaseURL: makeTempGraphURL())
        )

        #expect(decision?.source == .workflow)
        #expect(decision?.planDiagnostics == nil)
        #expect(decision?.workflowID == "workflow-compose")
    }

    @Test("Apply patch operator uses preferred fix path when available")
    func applyPatchOperatorUsesPreferredFixPath() {
        let state = ReasoningPlanningState(
            taskContext: TaskContext(
                goal: Goal(description: "fix calculator", workspaceRoot: "/tmp/workspace", preferredAgentKind: .code),
                agentKind: .code,
                workspaceRoot: "/tmp/workspace",
                phases: [.engineering]
            ),
            worldState: WorldState(
                observationHash: "workspace-state",
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
                    files: [RepositoryFile(path: "Sources/Example/Calculator.swift", isDirectory: false)],
                    symbolGraph: SymbolGraph(),
                    dependencyGraph: DependencyGraph(),
                    testGraph: TestGraph(),
                    activeBranch: "main",
                    isGitDirty: true
                )
            ),
            memoryInfluence: MemoryInfluence(preferredFixPath: "Sources/Example/Calculator.swift")
        )

        let contract = Operator(kind: .applyPatch).actionContract(
            for: state,
            goal: Goal(description: "fix calculator", workspaceRoot: "/tmp/workspace", preferredAgentKind: .code)
        )

        #expect(contract?.skillName == "edit_file")
        #expect(contract?.workspaceRelativePath == "Sources/Example/Calculator.swift")
    }

    @Test("Plan simulator prefers dismissing a modal before clicking through it")
    func planSimulatorPrefersDismissingModal() {
        let goal = Goal(
            description: "close the blocking modal and continue in Safari",
            targetApp: "Safari",
            preferredAgentKind: .os
        )
        let taskContext = TaskContext.from(goal: goal)
        let worldState = WorldState(
            observationHash: "safari-modal",
            planningState: planningState(
                id: "safari|dialog",
                appID: "Safari",
                domain: nil,
                taskPhase: "browse",
                modalClass: "dialog"
            ),
            observation: Observation(
                app: "Safari",
                windowTitle: "Safari",
                url: "https://example.com",
                focusedElementID: nil,
                elements: [
                    UnifiedElement(id: "dialog", source: .ax, role: "AXDialog", label: "Permission dialog", confidence: 0.95),
                    UnifiedElement(id: "continue", source: .ax, role: "AXButton", label: "Continue", confidence: 0.9),
                ]
            )
        )
        let memoryInfluence = MemoryInfluence()
        let reasoningState = ReasoningPlanningState(
            taskContext: taskContext,
            worldState: worldState,
            memoryInfluence: memoryInfluence
        )
        let modalPlan = PlanCandidate(
            operators: [Operator(kind: .dismissModal)],
            projectedState: Operator(kind: .dismissModal).effect(reasoningState)
        )
        let clickPlan = PlanCandidate(
            operators: [Operator(kind: .clickTarget)],
            projectedState: Operator(kind: .clickTarget).effect(reasoningState)
        )
        let simulator = PlanSimulator(workflowRetriever: WorkflowRetriever())
        let graphStore = GraphStore(databaseURL: makeTempGraphURL())

        let modalOutcome = simulator.simulate(
            plan: modalPlan,
            taskContext: taskContext,
            goal: goal,
            worldState: worldState,
            graphStore: graphStore,
            workflowIndex: WorkflowIndex(),
            memoryStore: UnifiedMemoryStore()
        )
        let clickOutcome = simulator.simulate(
            plan: clickPlan,
            taskContext: taskContext,
            goal: goal,
            worldState: worldState,
            graphStore: graphStore,
            workflowIndex: WorkflowIndex(),
            memoryStore: UnifiedMemoryStore()
        )

        #expect(modalOutcome != nil)
        #expect(clickOutcome != nil)
        #expect((modalOutcome?.successProbability ?? 0) > (clickOutcome?.successProbability ?? 0))
        #expect(clickOutcome?.likelyFailureMode == "modal-blocked")
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
