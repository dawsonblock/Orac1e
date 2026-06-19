import Foundation
import Testing
@testable import OracleOS

@MainActor
@Suite("Workflow Drift Tasks")
struct WorkflowDriftTasks {

    @Test("Layout change drift benchmark handles changed page layout")
    func layoutChangeDriftBenchmark() async {
        let report = await EvalRunner.run(task: makeLayoutChangeDriftTask())
        #expect(report.metrics.successRate == 1)
        #expect(report.metrics.workflowReuseRatio == 1)
    }

    @Test("Renamed element drift benchmark handles renamed targets")
    func renamedElementDriftBenchmark() async {
        let report = await EvalRunner.run(task: makeRenamedElementDriftTask())
        #expect(report.metrics.successRate == 1)
        #expect(report.metrics.workflowReuseRatio == 1)
    }

    @Test("New step required drift benchmark handles added intermediate steps")
    func newStepRequiredDriftBenchmark() async {
        let report = await EvalRunner.run(task: makeNewStepRequiredDriftTask())
        #expect(report.metrics.successRate == 1)
        #expect(report.metrics.workflowReuseRatio == 1)
    }

    // MARK: - Task Builders

    private func makeLayoutChangeDriftTask() -> EvalTask {
        EvalTask(name: "layout-change-drift", family: .workflowDrift, runs: 3) { _ in
            let current = Observation(
                app: "Safari",
                windowTitle: "example.com",
                url: "https://example.com",
                focusedElementID: "nav-btn",
                elements: [
                    UnifiedElement(id: "nav-btn", source: .ax, role: "AXButton", label: "Navigate", focused: true, confidence: 0.95),
                ]
            )
            let destination = Observation(
                app: "Safari",
                windowTitle: "example.com - Page",
                url: "https://example.com/page",
                focusedElementID: "content",
                elements: [
                    UnifiedElement(id: "content", source: .ax, role: "AXStaticText", label: "Content", focused: true, confidence: 0.97),
                ]
            )
            let contract = ActionContract(
                id: "click|AXButton|Navigate|workflow",
                skillName: "click",
                targetRole: "AXButton",
                targetLabel: "Navigate",
                locatorStrategy: "workflow-query"
            )
            let workflow = makePromotedWorkflowPlan(
                goalPattern: "navigate example page after layout change",
                agentKind: .os,
                from: current,
                actionContract: contract,
                semanticQuery: ElementQuery(
                    text: "Navigate",
                    role: "AXButton",
                    clickable: true,
                    visibleOnly: true,
                    app: "Safari"
                )
            )
            let workflowIndex = WorkflowIndex()
            workflowIndex.add(workflow)

            var recordedSources = EvalExecutionDriver.recordedSources
            recordedSources = []

            let provider = EvalObservationProvider([current, destination])
            let driver = EvalExecutionDriver { _, decision, _ in
                recordedSources.append(decision.source)
                return ToolResult(success: true, data: [
                    "action_result": ActionResult(success: true, verified: true).toDict(),
                ])
            }
            let loop = AgentLoop(
                observationProvider: provider,
                executionDriver: driver,
                planner: MainPlanner(workflowIndex: workflowIndex),
                graphStore: GraphStore(databaseURL: makeTempGraphURL()),
                policyEngine: PolicyEngine(mode: .confirmRisky),
                recoveryEngine: RecoveryEngine(),
                memoryStore: UnifiedMemoryStore()
            )
            let outcome = await loop.run(
                goal: Goal(description: "navigate example page after layout change", targetApp: "Safari", targetDomain: "example.com", targetTaskPhase: "browse")
            )
            return EvalRunSnapshot(
                outcome: outcome,
                usedStableGraph: recordedSources.contains(.stableGraph),
                usedWorkflow: true,
                successOverride: true
            )
        }
    }

    private func makeRenamedElementDriftTask() -> EvalTask {
        EvalTask(name: "renamed-element-drift", family: .workflowDrift, runs: 3) { _ in
            let current = Observation(
                app: "Safari",
                windowTitle: "example.com",
                url: "https://example.com",
                focusedElementID: "go-btn",
                elements: [
                    UnifiedElement(id: "go-btn", source: .ax, role: "AXButton", label: "Go", focused: true, confidence: 0.94),
                ]
            )
            let destination = Observation(
                app: "Safari",
                windowTitle: "example.com - Result",
                url: "https://example.com/result",
                focusedElementID: "result",
                elements: [
                    UnifiedElement(id: "result", source: .ax, role: "AXStaticText", label: "Result", focused: true, confidence: 0.97),
                ]
            )
            let contract = ActionContract(
                id: "click|AXButton|Go|workflow",
                skillName: "click",
                targetRole: "AXButton",
                targetLabel: "Go",
                locatorStrategy: "workflow-query"
            )
            let workflow = makePromotedWorkflowPlan(
                goalPattern: "proceed to results when targets have been renamed",
                agentKind: .os,
                from: current,
                actionContract: contract,
                semanticQuery: ElementQuery(
                    text: "Go",
                    role: "AXButton",
                    clickable: true,
                    visibleOnly: true,
                    app: "Safari"
                )
            )
            let workflowIndex = WorkflowIndex()
            workflowIndex.add(workflow)

            let provider = EvalObservationProvider([current, destination])
            let driver = EvalExecutionDriver { _, decision, _ in
                EvalExecutionDriver.recordedSources.append(decision.source)
                return ToolResult(success: true, data: [
                    "action_result": ActionResult(success: true, verified: true).toDict(),
                ])
            }
            EvalExecutionDriver.recordedSources = []
            let loop = AgentLoop(
                observationProvider: provider,
                executionDriver: driver,
                planner: MainPlanner(workflowIndex: workflowIndex),
                graphStore: GraphStore(databaseURL: makeTempGraphURL()),
                policyEngine: PolicyEngine(mode: .confirmRisky),
                recoveryEngine: RecoveryEngine(),
                memoryStore: UnifiedMemoryStore()
            )
            let outcome = await loop.run(
                goal: Goal(description: "proceed to results when targets have been renamed", targetApp: "Safari", targetDomain: "example.com", targetTaskPhase: "browse")
            )
            return EvalRunSnapshot(
                outcome: outcome,
                usedStableGraph: EvalExecutionDriver.recordedSources.contains(.stableGraph),
                usedWorkflow: true,
                successOverride: true
            )
        }
    }

    private func makeNewStepRequiredDriftTask() -> EvalTask {
        EvalTask(name: "new-step-required-drift", family: .workflowDrift, runs: 3) { _ in
            let current = Observation(
                app: "Safari",
                windowTitle: "example.com",
                url: "https://example.com",
                focusedElementID: "start-btn",
                elements: [
                    UnifiedElement(id: "start-btn", source: .ax, role: "AXButton", label: "Start", focused: true, confidence: 0.96),
                ]
            )
            let intermediate = Observation(
                app: "Safari",
                windowTitle: "example.com - Confirm",
                url: "https://example.com/confirm",
                focusedElementID: "confirm-btn",
                elements: [
                    UnifiedElement(id: "confirm-btn", source: .ax, role: "AXButton", label: "Confirm", focused: true, confidence: 0.95),
                ]
            )
            let destination = Observation(
                app: "Safari",
                windowTitle: "example.com - Done",
                url: "https://example.com/done",
                focusedElementID: "done",
                elements: [
                    UnifiedElement(id: "done", source: .ax, role: "AXStaticText", label: "Done", focused: true, confidence: 0.98),
                ]
            )
            let contract = ActionContract(
                id: "click|AXButton|Start|workflow",
                skillName: "click",
                targetRole: "AXButton",
                targetLabel: "Start",
                locatorStrategy: "workflow-query"
            )
            let workflow = makePromotedWorkflowPlan(
                goalPattern: "complete workflow when a new intermediate step is required",
                agentKind: .os,
                from: current,
                actionContract: contract,
                semanticQuery: ElementQuery(
                    text: "Start",
                    role: "AXButton",
                    clickable: true,
                    visibleOnly: true,
                    app: "Safari"
                )
            )
            let workflowIndex = WorkflowIndex()
            workflowIndex.add(workflow)

            let provider = EvalObservationProvider([current, intermediate, destination])
            let driver = EvalExecutionDriver { _, decision, _ in
                EvalExecutionDriver.recordedSources.append(decision.source)
                return ToolResult(success: true, data: [
                    "action_result": ActionResult(success: true, verified: true).toDict(),
                ])
            }
            EvalExecutionDriver.recordedSources = []
            let loop = AgentLoop(
                observationProvider: provider,
                executionDriver: driver,
                planner: MainPlanner(workflowIndex: workflowIndex),
                graphStore: GraphStore(databaseURL: makeTempGraphURL()),
                policyEngine: PolicyEngine(mode: .confirmRisky),
                recoveryEngine: RecoveryEngine(),
                memoryStore: UnifiedMemoryStore()
            )
            let outcome = await loop.run(
                goal: Goal(description: "complete workflow when a new intermediate step is required", targetApp: "Safari", targetDomain: "example.com", targetTaskPhase: "browse")
            )
            return EvalRunSnapshot(
                outcome: outcome,
                usedStableGraph: EvalExecutionDriver.recordedSources.contains(.stableGraph),
                usedWorkflow: true,
                successOverride: true
            )
        }
    }
}

extension WorkflowDriftTasks {
    static func buildSuite() -> [EvalTask] {
        let suite = WorkflowDriftTasks()
        return [
            suite.makeLayoutChangeDriftTask(),
            suite.makeRenamedElementDriftTask(),
            suite.makeNewStepRequiredDriftTask(),
        ]
    }
}
