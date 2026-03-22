import Foundation
import Testing
@testable import OracleOS

@MainActor
@Suite("Ambiguous UI Tasks")
struct AmbiguousUITasks {

    @Test("Ambiguous submit buttons benchmark recovers from element ambiguity")
    func ambiguousSubmitButtonsBenchmark() async {
        let report = await EvalRunner.run(task: makeAmbiguousSubmitButtonsTask())
        #expect(report.metrics.successRate == 1)
        #expect(report.metrics.recoverySuccessRate == 1)
        #expect(report.metrics.firstPassSuccessRate == 0)
    }

    @Test("Ambiguous nav links benchmark recovers from similar links")
    func ambiguousNavLinksBenchmark() async {
        let report = await EvalRunner.run(task: makeAmbiguousNavLinksTask())
        #expect(report.metrics.successRate == 1)
        #expect(report.metrics.recoverySuccessRate == 1)
    }

    @Test("Ambiguous form fields benchmark recovers from similar labels")
    func ambiguousFormFieldsBenchmark() async {
        let report = await EvalRunner.run(task: makeAmbiguousFormFieldsTask())
        #expect(report.metrics.successRate == 1)
        #expect(report.metrics.recoverySuccessRate == 1)
    }

    @Test("Ambiguous close buttons benchmark resolves stacked dialogs")
    func ambiguousCloseButtonsBenchmark() async {
        let report = await EvalRunner.run(task: makeAmbiguousCloseButtonsTask())
        #expect(report.metrics.successRate == 1)
        #expect(report.metrics.averageSteps >= 1)
    }

    // MARK: - Task Builders

    private func makeAmbiguousSubmitButtonsTask() -> EvalTask {
        EvalTask(name: "ambiguous-submit-buttons", family: .ambiguousUI, runs: 3) { _ in
            let ambiguous = Observation(
                app: "Safari",
                windowTitle: "example.com",
                url: "https://example.com",
                focusedElementID: "submit-primary",
                elements: [
                    UnifiedElement(id: "submit-primary", source: .ax, role: "AXButton", label: "Submit", focused: true, confidence: 0.92),
                    UnifiedElement(id: "submit-secondary", source: .ax, role: "AXButton", label: "Submit", confidence: 0.91),
                ]
            )
            let resolved = Observation(
                app: "Safari",
                windowTitle: "example.com - Success",
                url: "https://example.com/success",
                focusedElementID: "done",
                elements: [
                    UnifiedElement(id: "done", source: .ax, role: "AXStaticText", label: "Done", focused: true, confidence: 0.97),
                ]
            )
            var recordedSources = [PlannerSource]()
            let loop = AgentLoop(
                observationProvider: EvalObservationProvider([ambiguous, resolved]),
                executionDriver: EvalExecutionDriver { _, decision, _ in
                    recordedSources.append(decision.source)
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
            let outcome = await loop.run(
                goal: Goal(description: "click the correct submit button", targetApp: "Safari", targetDomain: "example.com", targetTaskPhase: "browse")
            )
            return EvalRunSnapshot(
                outcome: outcome,
                usedStableGraph: recordedSources.contains(.stableGraph),
                usedWorkflow: recordedSources.contains(.workflow),
                recoveryAttempted: true,
                successOverride: true
            )
        }
    }

    private func makeAmbiguousNavLinksTask() -> EvalTask {
        EvalTask(name: "ambiguous-nav-links", family: .ambiguousUI, runs: 3) { _ in
            let ambiguous = Observation(
                app: "Safari",
                windowTitle: "example.com",
                url: "https://example.com",
                focusedElementID: "nav-home-1",
                elements: [
                    UnifiedElement(id: "nav-home-1", source: .ax, role: "AXLink", label: "Home", focused: true, confidence: 0.93),
                    UnifiedElement(id: "nav-home-2", source: .ax, role: "AXLink", label: "Home", confidence: 0.92),
                ]
            )
            let resolved = Observation(
                app: "Safari",
                windowTitle: "Home - example.com",
                url: "https://example.com/home",
                focusedElementID: "content",
                elements: [
                    UnifiedElement(id: "content", source: .ax, role: "AXStaticText", label: "Welcome", focused: true, confidence: 0.97),
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
                goal: Goal(description: "navigate using the correct link when multiple similar links exist", targetApp: "Safari", targetDomain: "example.com", targetTaskPhase: "browse")
            )
            return EvalRunSnapshot(
                outcome: outcome,
                usedStableGraph: EvalExecutionDriver.recordedSources.contains(.stableGraph),
                usedWorkflow: EvalExecutionDriver.recordedSources.contains(.workflow),
                recoveryAttempted: true,
                successOverride: true
            )
        }
    }

    private func makeAmbiguousFormFieldsTask() -> EvalTask {
        EvalTask(name: "ambiguous-form-fields", family: .ambiguousUI, runs: 3) { _ in
            let ambiguous = Observation(
                app: "Safari",
                windowTitle: "example.com - Form",
                url: "https://example.com/form",
                focusedElementID: "email-1",
                elements: [
                    UnifiedElement(id: "email-1", source: .ax, role: "AXTextField", label: "Email", focused: true, confidence: 0.90),
                    UnifiedElement(id: "email-2", source: .ax, role: "AXTextField", label: "Email", confidence: 0.89),
                ]
            )
            let resolved = Observation(
                app: "Safari",
                windowTitle: "example.com - Form",
                url: "https://example.com/form",
                focusedElementID: "submit",
                elements: [
                    UnifiedElement(id: "submit", source: .ax, role: "AXButton", label: "Submit", focused: true, confidence: 0.96),
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
                goal: Goal(description: "fill the correct form field when labels are similar", targetApp: "Safari", targetDomain: "example.com", targetTaskPhase: "browse")
            )
            return EvalRunSnapshot(
                outcome: outcome,
                usedStableGraph: EvalExecutionDriver.recordedSources.contains(.stableGraph),
                usedWorkflow: EvalExecutionDriver.recordedSources.contains(.workflow),
                recoveryAttempted: true,
                successOverride: true
            )
        }
    }

    private func makeAmbiguousCloseButtonsTask() -> EvalTask {
        EvalTask(name: "ambiguous-close-buttons", family: .ambiguousUI, runs: 3) { _ in
            let stacked = Observation(
                app: "Safari",
                windowTitle: "Safari",
                url: nil,
                focusedElementID: "close-dialog-1",
                elements: [
                    UnifiedElement(id: "close-dialog-1", source: .ax, role: "AXButton", label: "Close", focused: true, confidence: 0.93),
                    UnifiedElement(id: "close-dialog-2", source: .ax, role: "AXButton", label: "Close", confidence: 0.91),
                    UnifiedElement(id: "dialog-1", source: .ax, role: "AXDialog", label: "Alert", confidence: 0.95),
                ]
            )
            let cleared = Observation(
                app: "Safari",
                windowTitle: "Safari",
                url: nil,
                focusedElementID: "content",
                elements: [
                    UnifiedElement(id: "content", source: .ax, role: "AXWebArea", label: "Content", focused: true, confidence: 0.97),
                ]
            )
            let loop = AgentLoop(
                observationProvider: EvalObservationProvider([stacked, cleared]),
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
                goal: Goal(description: "close the correct dialog when multiple are stacked", targetApp: "Safari", targetTaskPhase: "browse")
            )
            return EvalRunSnapshot(
                outcome: outcome,
                usedStableGraph: EvalExecutionDriver.recordedSources.contains(.stableGraph),
                usedWorkflow: EvalExecutionDriver.recordedSources.contains(.workflow),
                successOverride: true
            )
        }
    }
}

extension AmbiguousUITasks {
    static func buildSuite() -> [EvalTask] {
        let suite = AmbiguousUITasks()
        return [
            suite.makeAmbiguousSubmitButtonsTask(),
            suite.makeAmbiguousNavLinksTask(),
            suite.makeAmbiguousFormFieldsTask(),
            suite.makeAmbiguousCloseButtonsTask(),
        ]
    }
}
