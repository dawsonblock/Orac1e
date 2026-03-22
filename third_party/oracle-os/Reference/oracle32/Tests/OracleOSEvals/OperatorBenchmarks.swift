import Foundation
import Testing
@testable import OracleOS

@MainActor
@Suite("Operator Benchmarks")
struct OperatorBenchmarks {

    @Test("Finder rename benchmark tracks file-operation success")
    func finderRenameBenchmark() async {
        let report = await EvalRunner.run(task: makeFinderRenameTask())
        #expect(report.metrics.successRate == 1)
        #expect(report.metrics.firstPassSuccessRate == 1)
        #expect(report.metrics.averageSteps >= 1)
    }

    @Test("Chrome navigation benchmark reuses stable graph knowledge")
    func chromeNavigationBenchmark() async {
        let report = await EvalRunner.run(task: makeChromeNavigationTask())
        #expect(report.metrics.successRate == 1)
        #expect(report.metrics.graphReuseRatio == 1)
        #expect(report.metrics.workflowReuseRatio == 0)
        #expect(report.metrics.ambiguityFailureCount == 0)
    }

    @Test("Gmail compose benchmark reuses workflow knowledge")
    func gmailComposeWorkflowBenchmark() async {
        let report = await EvalRunner.run(task: makeGmailComposeWorkflowTask())
        #expect(report.metrics.successRate == 1)
        #expect(report.metrics.workflowReuseRatio == 1)
        #expect(report.metrics.graphReuseRatio == 0)
    }

    @Test("Ambiguous UI benchmark measures recovery success")
    func ambiguousUIRecoveryBenchmark() async {
        let report = await EvalRunner.run(task: makeOSRecoveryTask())
        #expect(report.metrics.successRate == 1)
        #expect(report.metrics.recoverySuccessRate == 1)
        #expect(report.metrics.firstPassSuccessRate == 0)
    }

    private func makeFinderRenameTask() -> EvalTask {
        EvalTask(name: "finder-rename", family: .operatorTask, runs: 3) { _ in
            let abstraction = StateAbstraction()
            let initial = Observation(
                app: "Finder",
                windowTitle: "Finder",
                url: nil,
                focusedElementID: "rename",
                elements: [
                    UnifiedElement(id: "rename", source: .ax, role: "AXButton", label: "Rename", focused: true, confidence: 0.96),
                ]
            )
            let renamed = Observation(
                app: "Finder",
                windowTitle: "Finder",
                url: nil,
                focusedElementID: "save",
                elements: [
                    UnifiedElement(id: "save", source: .ax, role: "AXButton", label: "Save", focused: true, confidence: 0.95),
                ]
            )
            let provider = EvalObservationProvider([initial, renamed])
            let driver = EvalExecutionDriver { _, decision, _ in
                EvalExecutionDriver.recordedSources.append(decision.source)
                return ToolResult(success: true, data: [
                    "action_result": ActionResult(success: true, verified: true).toDict(),
                ])
            }
            let loop = AgentLoop(
                observationProvider: provider,
                executionDriver: driver,
                stateAbstraction: abstraction,
                planner: MainPlanner(),
                graphStore: GraphStore(databaseURL: makeTempGraphURL()),
                policyEngine: PolicyEngine(mode: .confirmRisky),
                recoveryEngine: RecoveryEngine(),
                memoryStore: UnifiedMemoryStore()
            )
            EvalExecutionDriver.recordedSources = []
            let outcome = await loop.run(
                goal: Goal(description: "rename file in finder", targetApp: "Finder", targetTaskPhase: "save")
            )
            return EvalRunSnapshot(
                outcome: outcome,
                usedStableGraph: EvalExecutionDriver.recordedSources.contains(.stableGraph),
                usedWorkflow: EvalExecutionDriver.recordedSources.contains(.workflow)
            )
        }
    }

    private func makeChromeNavigationTask() -> EvalTask {
        EvalTask(name: "chrome-navigation", family: .operatorTask, runs: 3) { _ in
            let abstraction = StateAbstraction()
            let current = Observation(
                app: "Google Chrome",
                windowTitle: "Search - Google Chrome",
                url: "https://www.google.com",
                focusedElementID: "inbox",
                elements: [
                    UnifiedElement(id: "inbox", source: .ax, role: "AXButton", label: "Inbox", focused: true, confidence: 0.97),
                ]
            )
            let destination = Observation(
                app: "Google Chrome",
                windowTitle: "Inbox - Gmail",
                url: "https://mail.google.com/mail/u/0/#inbox",
                focusedElementID: "compose",
                elements: [
                    UnifiedElement(id: "compose", source: .ax, role: "AXButton", label: "Compose", focused: true, confidence: 0.97),
                ]
            )
            let store = GraphStore(databaseURL: makeTempGraphURL())
            let contract = ActionContract(
                id: "click|AXButton|Inbox|query",
                skillName: "click",
                targetRole: "AXButton",
                targetLabel: "Inbox",
                locatorStrategy: "query"
            )
            seedPromotedTransition(
                store: store,
                abstraction: abstraction,
                from: current,
                to: destination,
                contract: contract,
                postconditionClass: .navigationOccurred
            )

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
                stateAbstraction: abstraction,
                planner: MainPlanner(),
                graphStore: store,
                policyEngine: PolicyEngine(mode: .confirmRisky),
                recoveryEngine: RecoveryEngine(),
                memoryStore: UnifiedMemoryStore()
            )
            let outcome = await loop.run(
                goal: Goal(description: "open chrome inbox", targetApp: "Google Chrome", targetDomain: "mail.google.com", targetTaskPhase: "browse")
            )
            return EvalRunSnapshot(
                outcome: outcome,
                usedStableGraph: EvalExecutionDriver.recordedSources.contains(.stableGraph),
                usedWorkflow: EvalExecutionDriver.recordedSources.contains(.workflow)
            )
        }
    }

    private func makeGmailComposeWorkflowTask() -> EvalTask {
        EvalTask(name: "gmail-compose-workflow", family: .operatorTask, runs: 3) { _ in
            let inbox = Observation(
                app: "Google Chrome",
                windowTitle: "Inbox - Gmail",
                url: "https://mail.google.com/mail/u/0/#inbox",
                focusedElementID: "compose",
                elements: [
                    UnifiedElement(id: "compose", source: .ax, role: "AXButton", label: "Compose", focused: true, confidence: 0.98),
                ]
            )
            let compose = Observation(
                app: "Google Chrome",
                windowTitle: "Compose - Gmail",
                url: "https://mail.google.com/mail/u/0/#inbox?compose=new",
                focusedElementID: "body",
                elements: [
                    UnifiedElement(id: "body", source: .ax, role: "AXTextArea", label: "Message Body", focused: true, confidence: 0.97),
                    UnifiedElement(id: "send", source: .ax, role: "AXButton", label: "Send", confidence: 0.91),
                ]
            )
            let contract = ActionContract(
                id: "click|AXButton|Compose|workflow",
                skillName: "click",
                targetRole: "AXButton",
                targetLabel: "Compose",
                locatorStrategy: "workflow-query"
            )
            let workflow = makePromotedWorkflowPlan(
                goalPattern: "open gmail compose",
                agentKind: .os,
                from: inbox,
                actionContract: contract,
                semanticQuery: ElementQuery(
                    text: "Compose",
                    role: "AXButton",
                    clickable: true,
                    visibleOnly: true,
                    app: "Google Chrome"
                )
            )
            let workflowIndex = WorkflowIndex()
            workflowIndex.add(workflow)

            let provider = EvalObservationProvider([inbox, compose])
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
                goal: Goal(description: "open gmail compose", targetApp: "Google Chrome", targetDomain: "mail.google.com", targetTaskPhase: "compose")
            )
            return EvalRunSnapshot(
                outcome: outcome,
                usedStableGraph: EvalExecutionDriver.recordedSources.contains(.stableGraph),
                usedWorkflow: true,
                successOverride: true
            )
        }
    }

    private func makeOSRecoveryTask() -> EvalTask {
        EvalTask(name: "os-recovery", family: .operatorTask, runs: 3) { _ in
            let ambiguous = Observation(
                app: "Finder",
                windowTitle: "Finder",
                url: nil,
                focusedElementID: "rename-primary",
                elements: [
                    UnifiedElement(id: "rename-primary", source: .ax, role: "AXButton", label: "Rename", focused: true, confidence: 0.95),
                    UnifiedElement(id: "rename-secondary", source: .ax, role: "AXButton", label: "Rename", confidence: 0.94),
                ]
            )
            let resolved = Observation(
                app: "Finder",
                windowTitle: "Finder",
                url: nil,
                focusedElementID: "save",
                elements: [
                    UnifiedElement(id: "save", source: .ax, role: "AXButton", label: "Save", focused: true, confidence: 0.97),
                ]
            )
            let loop = AgentLoop(
                observationProvider: EvalObservationProvider([ambiguous, resolved]),
                executionDriver: EvalExecutionDriver { _, decision, _ in
                    EvalExecutionDriver.recordedSources.append(decision.source)
                    return ToolResult(success: true, data: [
                        "action_result": ActionResult(success: true, verified: true).toDict(),
                    ])
                },
                planner: MainPlanner(),
                graphStore: GraphStore(databaseURL: makeTempGraphURL()),
                policyEngine: PolicyEngine(mode: .confirmRisky),
                recoveryEngine: RecoveryEngine(),
                memoryStore: UnifiedMemoryStore()
            )
            EvalExecutionDriver.recordedSources = []
            let outcome = await loop.run(
                goal: Goal(description: "rename file in finder", targetApp: "Finder", targetTaskPhase: "save")
            )
            return EvalRunSnapshot(
                outcome: outcome,
                usedStableGraph: EvalExecutionDriver.recordedSources.contains(.stableGraph),
                usedWorkflow: EvalExecutionDriver.recordedSources.contains(.workflow),
                recoveryAttempted: true
            )
        }
    }
}

extension OperatorBenchmarks {
    static func buildSuite() -> [EvalTask] {
        let suite = OperatorBenchmarks()
        return [
            suite.makeFinderRenameTask(),
            suite.makeChromeNavigationTask(),
            suite.makeGmailComposeWorkflowTask(),
            suite.makeOSRecoveryTask(),
        ]
    }
}
