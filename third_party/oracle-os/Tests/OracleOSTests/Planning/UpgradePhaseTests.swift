import Foundation
import Testing
@testable import OracleOS

@Suite("Upgrade Phase Integration")
struct UpgradePhaseTests {

    // MARK: - Helpers

    private func makePlanningState(
        id: String,
        appID: String = "TestApp",
        domain: String? = "test.com",
        taskPhase: String? = "browse",
        modalClass: String? = nil
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

    private func makeWorldState(
        planningStateID: String,
        appID: String = "TestApp",
        taskPhase: String? = "browse",
        observationHash: String = "hash"
    ) -> WorldState {
        let ps = makePlanningState(id: planningStateID, appID: appID, taskPhase: taskPhase)
        return WorldState(
            observationHash: observationHash,
            planningState: ps,
            observation: Observation(app: appID, windowTitle: "Window", url: nil, focusedElementID: nil, elements: [])
        )
    }

    private func makeRepoWorldState(
        planningStateID: String,
        observationHash: String = "hash"
    ) -> WorldState {
        let ps = makePlanningState(id: planningStateID, appID: "Xcode", taskPhase: "editing")
        let repo = RepositorySnapshot(
            id: "test-repo",
            workspaceRoot: "/tmp/test-repo",
            branch: "main",
            dirty: false,
            trackedFileCount: 10,
            fileIndex: []
        )
        return WorldState(
            observationHash: observationHash,
            planningState: ps,
            observation: Observation(app: "Xcode", windowTitle: "Editor", url: nil, focusedElementID: nil, elements: []),
            repositorySnapshot: repo
        )
    }

    // MARK: - Phase 1: TaskLedgerStore exportJSON includes edge_success_rates

    @Test("TaskLedgerStore exportJSON includes edge_success_rates and current_node")
    func taskGraphStoreExportJSONEdgeSuccessRates() {
        let store = TaskLedgerStore()
        let ws = makeWorldState(planningStateID: "s1")
        store.updateCurrentNode(worldState: ws)

        let edge = store.addCandidateEdge(
            action: "navigate",
            toAbstractState: .navigationCompleted,
            toPlanningStateID: PlanningStateID(rawValue: "s2")
        )
        edge?.recordSuccess(latencyMs: 100)
        edge?.recordSuccess(latencyMs: 150)
        edge?.recordFailure(latencyMs: 200)

        let json = store.exportJSON()

        // Verify new fields
        let currentNode = json["current_node"] as? String
        #expect(currentNode?.isEmpty == false)

        let successRates = json["edge_success_rates"] as? [String: Any]
        #expect(successRates != nil)
        #expect(successRates?.count == 1)

        if let edgeID = edge?.id, let edgeRates = successRates?[edgeID] as? [String: Any] {
            let rate = edgeRates["success_rate"] as? Double
            #expect(rate != nil)
            guard let rate else { return }
            // 2 successes / 3 attempts ≈ 0.667
            #expect(abs(rate - (2.0 / 3.0)) < 0.01)
        }
    }

    // MARK: - Phase 2: LedgerNavigator beamWidth

    @Test("LedgerNavigator beamWidth limits the number of returned paths")
    func graphNavigatorBeamWidth() {
        let graph = TaskLedger(maxNodesPerTask: 200, maxEdgesPerNode: 10)
        let scorer = LedgerScorer()

        // Create a root node with many branching paths
        let root = TaskRecord(abstractState: .repoLoaded, planningStateID: PlanningStateID(rawValue: "root"))
        graph.addOrMergeNode(root)
        graph.setCurrent(root.id)

        // Create 6 target nodes with edges
        for i in 0..<6 {
            let target = TaskRecord(
                abstractState: .testsRunning,
                planningStateID: PlanningStateID(rawValue: "target-\(i)")
            )
            let addedTarget = graph.addOrMergeNode(target)
            let edge = TaskRecordEdge(
                fromNodeID: root.id,
                toNodeID: addedTarget.id,
                action: "action_\(i)",
                status: .candidate
            )
            graph.addEdge(edge)
        }

        // Use a small beamWidth
        let navigator = LedgerNavigator(maxDepth: 2, maxBranching: 10, beamWidth: 3)
        let paths = navigator.expand(from: root.id, in: graph, scorer: scorer)

        // beamWidth * maxDepth = 3 * 2 = 6, limiting the total returned paths
        #expect(paths.count <= navigator.beamWidth * navigator.maxDepth)
    }

    @Test("LedgerNavigator default beamWidth is 4")
    func graphNavigatorDefaultBeamWidth() {
        let navigator = LedgerNavigator()
        #expect(navigator.beamWidth == 4)
        #expect(navigator.maxDepth == 3)
        #expect(navigator.maxBranching == 5)
    }

    // MARK: - Phase 4: LedgerScorer ScoreBreakdown includes memory_bias

    @Test("LedgerScorer scoreEdgeWithBreakdown returns memory_bias contribution")
    func graphScorerBreakdownMemoryBias() {
        let scorer = LedgerScorer()
        let edge = TaskRecordEdge(
            fromNodeID: "a",
            toNodeID: "b",
            action: "test_action",
            status: .candidate
        )
        edge.recordSuccess()

        let breakdown = scorer.scoreEdgeWithBreakdown(
            edge,
            goalState: .testsPassed,
            targetState: .testsRunning,
            memoryBias: 0.5
        )

        // Memory bias should contribute to the score
        #expect(breakdown.memoryBias > 0)
        #expect(breakdown.memoryBias == scorer.memoryWeight * 0.5)
        #expect(breakdown.total > 0)

        // Breakdown total should match regular scoreEdge
        let regularScore = scorer.scoreEdge(
            edge,
            goalState: .testsPassed,
            targetState: .testsRunning,
            memoryBias: 0.5
        )
        #expect(abs(breakdown.total - regularScore) < 0.001)
    }

    @Test("LedgerScorer ScoreBreakdown toDict contains all fields")
    func graphScorerBreakdownToDict() {
        let scorer = LedgerScorer()
        let edge = TaskRecordEdge(
            fromNodeID: "a",
            toNodeID: "b",
            action: "click",
            status: .candidate
        )

        let breakdown = scorer.scoreEdgeWithBreakdown(edge, memoryBias: 0.3)
        let dict = breakdown.toDict()

        #expect(dict["predicted_success"] != nil)
        #expect(dict["workflow_similarity"] != nil)
        #expect(dict["memory_bias"] != nil)
        #expect(dict["goal_alignment"] != nil)
        #expect(dict["cost_penalty"] != nil)
        #expect(dict["risk_penalty"] != nil)
        #expect(dict["novelty_bonus"] != nil)
        #expect(dict["total"] != nil)
    }

    // MARK: - Phase 5: WorkflowMatcher

    @Test("WorkflowMatcher returns empty for no matching workflows")
    func workflowMatcherNoMatch() {
        let matcher = WorkflowMatcher()
        let index = WorkflowIndex()
        let matches = matcher.match(currentState: .repoLoaded, workflowIndex: index)
        #expect(matches.isEmpty)
    }

    // MARK: - Phase 7: DiagnosticsWriter

    @Test("DiagnosticsWriter writes task_graph.json")
    func diagnosticsWriterTaskGraph() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagnostics-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let writer = DiagnosticsWriter(outputDirectory: tmpDir)
        let store = TaskLedgerStore()
        let ws = makeWorldState(planningStateID: "s1")
        store.updateCurrentNode(worldState: ws)
        store.addCandidateEdge(
            action: "click",
            toAbstractState: .navigationCompleted,
            toPlanningStateID: PlanningStateID(rawValue: "s2")
        )

        writer.writeTaskGraph(store)

        let fileURL = tmpDir.appendingPathComponent("task_graph.json")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        let data = try Data(contentsOf: fileURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["nodes"] != nil)
        #expect(json?["edges"] != nil)
        #expect(json?["current_node"] != nil)
        #expect(json?["edge_success_rates"] != nil)
    }

    @Test("DiagnosticsWriter writes planner_paths.json")
    func diagnosticsWriterPlannerPaths() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagnostics-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let writer = DiagnosticsWriter(outputDirectory: tmpDir)
        let path = DiagnosticsWriter.PathSnapshot(
            edgeIDs: ["e1", "e2"],
            actions: ["click", "type"],
            terminalState: "goal_reached",
            score: 0.85,
            scoreBreakdowns: [["total": 0.5], ["total": 0.35]]
        )
        writer.writePlannerPaths(candidatePaths: [path], selectedPath: path)

        let fileURL = tmpDir.appendingPathComponent("planner_paths.json")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        let data = try Data(contentsOf: fileURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = json?["candidate_paths"] as? [[String: Any]]
        #expect(candidates?.count == 1)
        #expect(json?["selected_path"] != nil)
        #expect(json?["scores"] != nil)
    }

    @Test("DiagnosticsWriter writes patch_experiments.json")
    func diagnosticsWriterPatchExperiments() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagnostics-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let writer = DiagnosticsWriter(outputDirectory: tmpDir)
        let candidate = DiagnosticsWriter.PatchCandidateSnapshot(
            candidateID: "c1",
            strategy: "BoundaryFix",
            testsPassed: true,
            buildSucceeded: true,
            selected: true
        )
        let experiment = DiagnosticsWriter.PatchExperimentSnapshot(
            experimentID: "exp1",
            errorSignature: "NullPointerException",
            candidates: [candidate],
            selectedCandidateID: "c1"
        )
        writer.writePatchExperiments([experiment])

        let fileURL = tmpDir.appendingPathComponent("patch_experiments.json")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        let data = try Data(contentsOf: fileURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let experiments = json?["experiments"] as? [[String: Any]]
        #expect(experiments?.count == 1)
    }

    @Test("DiagnosticsWriter pathSnapshot builds from ScoredPath with score breakdowns")
    func diagnosticsWriterPathSnapshot() {
        let scorer = LedgerScorer()
        let node1 = TaskRecord(abstractState: .repoLoaded, planningStateID: PlanningStateID(rawValue: "s1"))
        let node2 = TaskRecord(abstractState: .testsRunning, planningStateID: PlanningStateID(rawValue: "s2"))
        let edge = TaskRecordEdge(
            fromNodeID: node1.id,
            toNodeID: node2.id,
            action: "run_tests",
            status: .candidate
        )

        let scoredPath = LedgerNavigator.ScoredPath(
            edges: [edge],
            nodes: [node1, node2],
            cumulativeScore: 0.5,
            terminalState: .testsRunning
        )

        let snapshot = DiagnosticsWriter.pathSnapshot(
            from: scoredPath,
            scorer: scorer,
            goalState: .testsPassed,
            memoryBias: 0.2
        )

        #expect(snapshot.edgeIDs.count == 1)
        #expect(snapshot.actions == ["run_tests"])
        #expect(snapshot.terminalState == "tests_running")
        #expect(!snapshot.scoreBreakdowns.isEmpty)

        let breakdown = snapshot.scoreBreakdowns.first
        #expect(breakdown?["memory_bias"] != nil)
    }
}
