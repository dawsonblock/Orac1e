import Foundation
import Testing
@testable import OracleOS

@Suite("Strategy Diagnostics")
struct StrategyDiagnosticsTests {

    @Test("StrategyDiagnostics produces valid dictionary")
    func diagnosticsToDict() {
        let diag = StrategyDiagnostics(
            selectedStrategy: .repoRepair,
            confidence: 0.85,
            rationale: "tests failing with repo open",
            allowedOperatorFamilies: [.repoAnalysis, .patchGeneration, .recovery],
            candidateCountBeforeFiltering: 10,
            candidateCountAfterFiltering: 4,
            reevaluationCause: .stepThresholdReached
        )
        let dict = diag.toDict()

        #expect(dict["strategy"] as? String == "repo_repair")
        #expect(dict["confidence"] as? Double == 0.85)
        #expect(dict["reevaluation_cause"] as? String == "step_threshold_reached")
        let families = dict["allowed_operator_families"] as? [String] ?? []
        #expect(families.count == 3)
        #expect(families.contains("repo_analysis"))
    }

    @Test("StrategyDiagnosticsWriter records and returns entries")
    func diagnosticsWriterRecords() {
        let writer = StrategyDiagnosticsWriter(outputDirectory: URL(fileURLWithPath: "/tmp/oracleos-test-diagnostics"))

        let strategy = SelectedStrategy(
            kind: .browserInteraction,
            confidence: 0.7,
            rationale: "browser active",
            allowedOperatorFamilies: [.browserTargeted, .recovery]
        )
        writer.record(strategy: strategy)

        let entries = writer.recentEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.selectedStrategy == .browserInteraction)
    }

    @Test("DiagnosticsWriter can write strategy selection")
    func diagnosticsWriterWritesStrategy() {
        let outputDir = URL(fileURLWithPath: "/tmp/oracleos-test-diagnostics-\(UUID().uuidString)")
        let writer = DiagnosticsWriter(outputDirectory: outputDir)

        let strategy = SelectedStrategy(
            kind: .recoveryMode,
            confidence: 0.9,
            rationale: "repeated failures",
            allowedOperatorFamilies: [.recovery, .graphEdge]
        )
        writer.writeStrategySelection(strategy, reevaluationCause: .hardFailure)

        // Verify the file was written
        let fileURL = outputDir.appendingPathComponent("strategy_selection.json")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        // Cleanup
        try? FileManager.default.removeItem(at: outputDir)
    }

    @Test("PostconditionVerifier detects click without effect")
    func postconditionVerifierClickNoEffect() {
        let verifier = PostconditionVerifier()
        let state = makeWorldState(app: "Safari", hash: "same_hash")

        let result = verifier.verify(
            action: "click_target",
            target: "submit_button",
            preState: state,
            postState: state,
            latencyMs: 100
        )

        #expect(!result.passed)
        #expect(result.failureClass == "click_no_effect")
    }

    @Test("PostconditionVerifier passes when state changes after click")
    func postconditionVerifierClickWithEffect() {
        let verifier = PostconditionVerifier()
        let preState = makeWorldState(app: "Safari", hash: "hash_before")
        let postState = makeWorldState(app: "Safari", hash: "hash_after")

        let result = verifier.verify(
            action: "click_target",
            target: "submit_button",
            preState: preState,
            postState: postState,
            latencyMs: 50
        )

        #expect(result.passed)
        #expect(result.failureClass == nil)
    }

    @Test("TaskRecord stateSignature combines abstract state and planning state")
    func taskNodeStateSignature() {
        let node = TaskRecord(
            abstractState: .repoLoaded,
            planningStateID: PlanningStateID(rawValue: "test-state")
        )
        #expect(node.stateSignature == "repo_loaded|test-state")
    }

    // MARK: - Helpers

    private func makeWorldState(app: String, hash: String) -> WorldState {
        WorldState(
            observationHash: hash,
            planningState: PlanningState(
                id: PlanningStateID(rawValue: "\(app)|state"),
                clusterKey: StateClusterKey(rawValue: "\(app)|state"),
                appID: app,
                domain: nil,
                windowClass: nil,
                taskPhase: "test",
                focusedRole: nil,
                modalClass: nil,
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
            repositorySnapshot: nil
        )
    }
}
