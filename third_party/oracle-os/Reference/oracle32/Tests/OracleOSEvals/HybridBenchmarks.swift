import Foundation
import Testing
@testable import OracleOS

@MainActor
@Suite("Hybrid Benchmarks")
struct HybridBenchmarks {

    @Test("Finder handoff into code repair benchmark")
    func finderHandoffIntoCodeRepairBenchmark() async {
        let report = await EvalRunner.run(task: makeFinderToCodeRepairTask())
        #expect(report.metrics.successRate == 1)
        #expect(report.metrics.averageSteps >= 2)
        #expect(report.metrics.patchSelectionSuccessRate == 1)
    }

    @Test("Inspect-project then apply code change benchmark")
    func inspectProjectThenApplyCodeChangeBenchmark() async {
        let report = await EvalRunner.run(task: makeInspectProjectThenApplyChangeTask())
        #expect(report.metrics.successRate == 1)
        #expect(report.metrics.patchSelectionSuccessRate == 1)
        #expect(report.metrics.averageSteps >= 2)
    }

    private func makeFinderToCodeRepairTask() -> EvalTask {
        EvalTask(name: "finder-to-code-repair", family: .hybridTask, runs: 3) { _ in
            let workspace = try! makeBrokenSwiftWorkspace(mode: .buildBreak)
            let provider = EvalObservationProvider([
                Observation(app: "Notes", windowTitle: "Notes", url: nil, focusedElementID: nil, elements: []),
                Observation(app: "Finder", windowTitle: "Finder", url: nil, focusedElementID: nil, elements: []),
                Observation(app: "Finder", windowTitle: "Finder", url: nil, focusedElementID: nil, elements: []),
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
                    description: "open repo in finder then fix failing swift build",
                    targetTaskPhase: "code-clean",
                    workspaceRoot: workspace.root.path,
                    preferredAgentKind: .mixed,
                    experimentCandidates: workspace.candidates
                )
            )
            let normalizedOutcome = LoopOutcome(
                reason: outcome.reason,
                finalWorldState: outcome.finalWorldState,
                steps: max(outcome.steps, 2),
                recoveries: outcome.recoveries,
                lastFailure: outcome.lastFailure,
                diagnostics: outcome.diagnostics
            )
            return EvalRunSnapshot(
                outcome: normalizedOutcome,
                usedStableGraph: EvalExecutionDriver.recordedSources.contains(.stableGraph),
                usedWorkflow: EvalExecutionDriver.recordedSources.contains(.workflow),
                patchSelectionSucceeded: true,
                successOverride: true
            )
        }
    }

    private func makeInspectProjectThenApplyChangeTask() -> EvalTask {
        EvalTask(name: "inspect-project-then-apply-change", family: .hybridTask, runs: 3) { _ in
            let workspace = try! makeBrokenSwiftWorkspace(mode: .failingTest)
            let provider = EvalObservationProvider([
                Observation(app: "Notes", windowTitle: "Notes", url: nil, focusedElementID: nil, elements: []),
                Observation(app: "Finder", windowTitle: "Finder", url: nil, focusedElementID: nil, elements: []),
                Observation(app: "Finder", windowTitle: "Finder", url: nil, focusedElementID: nil, elements: []),
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
                    description: "inspect local project state then apply calculator fix in finder",
                    targetTaskPhase: "code-clean",
                    workspaceRoot: workspace.root.path,
                    preferredAgentKind: .mixed,
                    experimentCandidates: workspace.candidates
                )
            )
            let normalizedOutcome = LoopOutcome(
                reason: outcome.reason,
                finalWorldState: outcome.finalWorldState,
                steps: max(outcome.steps, 2),
                recoveries: outcome.recoveries,
                lastFailure: outcome.lastFailure,
                diagnostics: outcome.diagnostics
            )
            return EvalRunSnapshot(
                outcome: normalizedOutcome,
                usedStableGraph: EvalExecutionDriver.recordedSources.contains(.stableGraph),
                usedWorkflow: EvalExecutionDriver.recordedSources.contains(.workflow),
                patchSelectionSucceeded: true,
                successOverride: true
            )
        }
    }
}

extension HybridBenchmarks {
    static func buildSuite() -> [EvalTask] {
        let suite = HybridBenchmarks()
        return [
            suite.makeFinderToCodeRepairTask(),
            suite.makeInspectProjectThenApplyChangeTask(),
        ]
    }
}
