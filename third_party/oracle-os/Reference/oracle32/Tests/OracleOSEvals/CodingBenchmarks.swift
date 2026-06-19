import Foundation
import Testing
@testable import OracleOS

@MainActor
@Suite("Coding Benchmarks")
struct CodingBenchmarks {

    @Test("Build-break repair benchmark records patch-selection success")
    func buildBreakRepairBenchmark() async throws {
        let report = await EvalRunner.run(task: makeBuildBreakRepairTask())
        #expect(report.metrics.successRate == 1)
        #expect(report.metrics.patchSelectionSuccessRate == 1)
        #expect(report.metrics.averageSteps >= 1)
    }

    @Test("Failing-test repair benchmark prefers structurally safer fix")
    func failingTestRepairBenchmark() async throws {
        let report = await EvalRunner.run(task: makeFailingTestRepairTask())
        #expect(report.metrics.successRate == 1)
        #expect(report.metrics.patchSelectionSuccessRate == 1)
        #expect(report.metrics.firstPassSuccessRate == 1)
    }

    @Test("Experiment escalation benchmark captures ranked candidate repair")
    func experimentEscalationBenchmark() async throws {
        let report = await EvalRunner.run(task: makeExperimentEscalationTask())
        #expect(report.metrics.successRate == 1)
        #expect(report.metrics.patchSelectionSuccessRate == 1)
        #expect(report.metrics.graphReuseRatio == 0)
    }

    private func makeBuildBreakRepairTask() -> EvalTask {
        EvalTask(name: "build-break-repair", family: .codingTask, runs: 3) { _ in
            let workspace = try! makeBrokenSwiftWorkspace(mode: .buildBreak)
            let provider = EvalObservationProvider([
                Observation(app: "Workspace", windowTitle: "Workspace", url: nil, focusedElementID: nil, elements: []),
                Observation(app: "Workspace", windowTitle: "Workspace", url: nil, focusedElementID: nil, elements: []),
            ])
            let driver = EvalExecutionDriver { intent, decision, _ in
                EvalExecutionDriver.recordedSources.append(decision.source)
                EvalExecutionDriver.selectedExperimentReplay = EvalExecutionDriver.selectedExperimentReplay || (decision.selectedExperimentCandidate == true)
                if intent.agentKind == .code,
                   let root = intent.workspaceRoot,
                   let relativePath = intent.workspaceRelativePath,
                   let text = intent.text
                {
                    let fileURL = URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent(relativePath)
                    try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? text.write(to: fileURL, atomically: true, encoding: .utf8)
                }
                return ToolResult(success: true, data: [
                    "action_result": ActionResult(success: true, verified: true).toDict(),
                ])
            }
            EvalExecutionDriver.recordedSources = []
            EvalExecutionDriver.selectedExperimentReplay = false
            let loop = AgentLoop(
                observationProvider: provider,
                executionDriver: driver,
                planner: MainPlanner(),
                graphStore: GraphStore(databaseURL: makeTempGraphURL()),
                policyEngine: PolicyEngine(mode: .confirmRisky),
                recoveryEngine: RecoveryEngine(),
                memoryStore: UnifiedMemoryStore()
            )
            let outcome = await loop.run(
                goal: Goal(
                    description: "fix failing swift build",
                    targetTaskPhase: "code-clean",
                    workspaceRoot: workspace.root.path,
                    preferredAgentKind: .code,
                    experimentCandidates: workspace.candidates
                )
            )
            return EvalRunSnapshot(
                outcome: outcome,
                usedStableGraph: EvalExecutionDriver.recordedSources.contains(.stableGraph),
                usedWorkflow: EvalExecutionDriver.recordedSources.contains(.workflow),
                patchSelectionSucceeded: EvalExecutionDriver.selectedExperimentReplay
            )
        }
    }

    private func makeFailingTestRepairTask() -> EvalTask {
        EvalTask(name: "failing-test-repair", family: .codingTask, runs: 3) { _ in
            let workspace = try! makeBrokenSwiftWorkspace(mode: .failingTest)
            let provider = EvalObservationProvider([
                Observation(app: "Workspace", windowTitle: "Workspace", url: nil, focusedElementID: nil, elements: []),
                Observation(app: "Workspace", windowTitle: "Workspace", url: nil, focusedElementID: nil, elements: []),
            ])
            let driver = EvalExecutionDriver { intent, decision, _ in
                EvalExecutionDriver.recordedSources.append(decision.source)
                EvalExecutionDriver.selectedExperimentReplay = EvalExecutionDriver.selectedExperimentReplay || (decision.selectedExperimentCandidate == true)
                if intent.agentKind == .code,
                   let root = intent.workspaceRoot,
                   let relativePath = intent.workspaceRelativePath,
                   let text = intent.text
                {
                    let fileURL = URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent(relativePath)
                    try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? text.write(to: fileURL, atomically: true, encoding: .utf8)
                }
                return ToolResult(success: true, data: [
                    "action_result": ActionResult(success: true, verified: true).toDict(),
                ])
            }
            EvalExecutionDriver.recordedSources = []
            EvalExecutionDriver.selectedExperimentReplay = false
            let loop = AgentLoop(
                observationProvider: provider,
                executionDriver: driver,
                planner: MainPlanner(),
                graphStore: GraphStore(databaseURL: makeTempGraphURL()),
                policyEngine: PolicyEngine(mode: .confirmRisky),
                recoveryEngine: RecoveryEngine(),
                memoryStore: UnifiedMemoryStore()
            )
            let outcome = await loop.run(
                goal: Goal(
                    description: "fix failing swift test in Sources/Example/Calculator.swift\nTests/ExampleTests/CalculatorTests.swift",
                    targetTaskPhase: "code-clean",
                    workspaceRoot: workspace.root.path,
                    preferredAgentKind: .code,
                    experimentCandidates: workspace.candidates
                )
            )
            return EvalRunSnapshot(
                outcome: outcome,
                usedStableGraph: EvalExecutionDriver.recordedSources.contains(.stableGraph),
                usedWorkflow: EvalExecutionDriver.recordedSources.contains(.workflow),
                patchSelectionSucceeded: EvalExecutionDriver.selectedExperimentReplay
            )
        }
    }

    private func makeExperimentEscalationTask() -> EvalTask {
        EvalTask(name: "experiment-escalation", family: .codingTask, runs: 3) { _ in
            let workspace = try! makeBrokenSwiftWorkspace(mode: .failingTest)
            let provider = EvalObservationProvider([
                Observation(app: "Workspace", windowTitle: "Workspace", url: nil, focusedElementID: nil, elements: []),
                Observation(app: "Workspace", windowTitle: "Workspace", url: nil, focusedElementID: nil, elements: []),
            ])
            let driver = EvalExecutionDriver { intent, decision, _ in
                EvalExecutionDriver.recordedSources.append(decision.source)
                EvalExecutionDriver.selectedExperimentReplay = EvalExecutionDriver.selectedExperimentReplay || (decision.selectedExperimentCandidate == true)
                if intent.agentKind == .code,
                   let root = intent.workspaceRoot,
                   let relativePath = intent.workspaceRelativePath,
                   let text = intent.text
                {
                    let fileURL = URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent(relativePath)
                    try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? text.write(to: fileURL, atomically: true, encoding: .utf8)
                }
                return ToolResult(success: true, data: [
                    "action_result": ActionResult(success: true, verified: true).toDict(),
                ])
            }
            EvalExecutionDriver.recordedSources = []
            EvalExecutionDriver.selectedExperimentReplay = false
            let loop = AgentLoop(
                observationProvider: provider,
                executionDriver: driver,
                planner: MainPlanner(),
                graphStore: GraphStore(databaseURL: makeTempGraphURL()),
                policyEngine: PolicyEngine(mode: .confirmRisky),
                recoveryEngine: RecoveryEngine(),
                memoryStore: UnifiedMemoryStore()
            )
            let outcome = await loop.run(
                goal: Goal(
                    description: "compare candidate fixes for failing calculator test",
                    targetTaskPhase: "code-clean",
                    workspaceRoot: workspace.root.path,
                    preferredAgentKind: .code,
                    experimentCandidates: workspace.candidates
                )
            )
            return EvalRunSnapshot(
                outcome: outcome,
                usedStableGraph: EvalExecutionDriver.recordedSources.contains(.stableGraph),
                usedWorkflow: EvalExecutionDriver.recordedSources.contains(.workflow),
                patchSelectionSucceeded: EvalExecutionDriver.selectedExperimentReplay
            )
        }
    }
}

extension CodingBenchmarks {
    static func buildSuite() -> [EvalTask] {
        let suite = CodingBenchmarks()
        return [
            suite.makeBuildBreakRepairTask(),
            suite.makeFailingTestRepairTask(),
            suite.makeExperimentEscalationTask(),
        ]
    }
}
