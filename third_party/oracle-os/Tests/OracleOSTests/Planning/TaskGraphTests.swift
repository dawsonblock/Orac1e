import Foundation
import Testing
@testable import OracleOS

@Suite("TaskLedger Substrate")
struct TaskGraphTests {

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
        planningState: PlanningState,
        app: String = "TestApp",
        repo: RepositorySnapshot? = nil
    ) -> WorldState {
        let observation = Observation(
            app: app,
            windowTitle: "Test Window",
            url: nil,
            focusedElementID: nil,
            elements: []
        )
        return WorldState(
            observation: observation,
            repositorySnapshot: repo
        )
    }

    private func makeRepoSnapshot() -> RepositorySnapshot {
        RepositorySnapshot(
            id: "test-repo",
            workspaceRoot: "/tmp/test-repo",
            branch: "main",
            dirty: false,
            trackedFileCount: 10,
            fileIndex: []
        )
    }

    // MARK: - TaskRecord Tests

    @Test("TaskRecord records visits and attaches memory refs")
    func taskNodeRecordsVisitsAndMemory() {
        let node = TaskRecord(
            abstractState: .repoLoaded,
            planningStateID: PlanningStateID(rawValue: "test|state")
        )
        #expect(node.visitCount == 0)
        node.recordVisit()
        node.recordVisit()
        #expect(node.visitCount == 2)

        node.attachMemoryRef("mem-1")
        node.attachMemoryRef("mem-2")
        node.attachMemoryRef("mem-1") // duplicate
        #expect(node.attachedMemoryRefs.count == 2)
    }

    @Test("TaskRecord attaches workflow matches without duplicates")
    func taskNodeWorkflowMatches() {
        let node = TaskRecord(
            abstractState: .testsRunning,
            planningStateID: PlanningStateID(rawValue: "test|run")
        )
        node.attachWorkflowMatch("wf-1")
        node.attachWorkflowMatch("wf-2")
        node.attachWorkflowMatch("wf-1")
        #expect(node.workflowMatches.count == 2)
    }

    @Test("TaskRecord confidence is bounded between 0 and 1")
    func taskNodeConfidenceBounds() {
        let node = TaskRecord(
            abstractState: .idle,
            planningStateID: PlanningStateID(rawValue: "idle")
        )
        node.updateConfidence(1.5)
        #expect(node.confidence == 1.0)
        node.updateConfidence(-0.5)
        #expect(node.confidence == 0.0)
        node.updateConfidence(0.7)
        #expect(node.confidence == 0.7)
    }

    // MARK: - TaskRecordEdge Tests

    @Test("TaskRecordEdge accumulates evidence correctly")
    func taskEdgeEvidenceAccumulation() {
        let edge = TaskRecordEdge(
            fromNodeID: "A",
            toNodeID: "B",
            action: "run_tests"
        )
        #expect(edge.attempts == 0)
        #expect(edge.successProbability == 0)

        edge.recordSuccess(latencyMs: 100, cost: 1.0)
        edge.recordSuccess(latencyMs: 200, cost: 2.0)
        edge.recordFailure(latencyMs: 50, cost: 0.5)

        #expect(edge.attempts == 3)
        #expect(edge.successCount == 2)
        #expect(edge.failureCount == 1)
        #expect(edge.totalLatencyMs == 350)
        #expect(edge.totalCost == 3.5)
        #expect(edge.averageLatencyMs > 116 && edge.averageLatencyMs < 117)
        #expect(edge.averageCost > 1.16 && edge.averageCost < 1.17)
    }

    @Test("TaskRecordEdge success probability computed from evidence")
    func taskEdgeSuccessProbability() {
        let edge = TaskRecordEdge(
            fromNodeID: "A",
            toNodeID: "B",
            action: "click_button"
        )
        edge.recordSuccess()
        edge.recordSuccess()
        edge.recordSuccess()
        edge.recordFailure()
        // P(success) = 3/4 = 0.75
        #expect(edge.successProbability == 0.75)
    }

    @Test("TaskRecordEdge status transitions correctly")
    func taskEdgeStatusTransitions() {
        let edge = TaskRecordEdge(
            fromNodeID: "A",
            toNodeID: "B",
            action: "navigate"
        )
        #expect(edge.status == .candidate)

        edge.recordSuccess()
        #expect(edge.status == .executedSuccess)

        edge.recordFailure()
        #expect(edge.status == .executedFailure)

        edge.markAbandoned()
        #expect(edge.status == .abandoned)
    }

    @Test("TaskRecordEdge risk is bounded between 0 and 1")
    func taskEdgeRiskBounds() {
        let edge = TaskRecordEdge(fromNodeID: "A", toNodeID: "B", action: "test")
        edge.updateRisk(1.5)
        #expect(edge.risk == 1.0)
        edge.updateRisk(-0.5)
        #expect(edge.risk == 0.0)
    }

    // MARK: - TaskLedger Tests

    @Test("TaskLedger maintains current node pointer")
    func taskGraphCurrentNode() {
        let graph = TaskLedger()
        #expect(graph.currentNode() == nil)

        let node = TaskRecord(
            abstractState: .repoLoaded,
            planningStateID: PlanningStateID(rawValue: "state-1")
        )
        graph.addOrMergeNode(node)
        graph.setCurrent(node.id)

        #expect(graph.currentNodeID == node.id)
        #expect(graph.currentNode()?.abstractState == .repoLoaded)
    }

    @Test("TaskLedger merges nodes with same abstract state and planning state ID")
    func taskGraphMergesNodes() {
        let graph = TaskLedger()
        let planningID = PlanningStateID(rawValue: "same|state")

        let node1 = TaskRecord(abstractState: .repoLoaded, planningStateID: planningID)
        let node2 = TaskRecord(abstractState: .repoLoaded, planningStateID: planningID)

        let added1 = graph.addOrMergeNode(node1)
        let added2 = graph.addOrMergeNode(node2)

        // Second add should return the existing node, not create a new one
        #expect(added1.id == added2.id)
        #expect(graph.nodeCount == 1)
        #expect(added1.visitCount == 2) // merged duplicate increments the existing node visit count
    }

    @Test("TaskLedger does not merge nodes with different abstract states")
    func taskGraphNoMergeDifferentStates() {
        let graph = TaskLedger()
        let planningID = PlanningStateID(rawValue: "state")

        let node1 = TaskRecord(abstractState: .repoLoaded, planningStateID: planningID)
        let node2 = TaskRecord(abstractState: .testsRunning, planningStateID: planningID)

        graph.addOrMergeNode(node1)
        graph.addOrMergeNode(node2)

        #expect(graph.nodeCount == 2)
    }

    @Test("TaskLedger enforces max nodes per task")
    func taskGraphMaxNodes() {
        let graph = TaskLedger(maxNodesPerTask: 5)

        for i in 0..<10 {
            let node = TaskRecord(
                abstractState: .idle,
                planningStateID: PlanningStateID(rawValue: "state-\(i)")
            )
            graph.addOrMergeNode(node)
        }

        #expect(graph.nodeCount <= 5)
    }

    @Test("TaskLedger adds and queries edges")
    func taskGraphEdges() {
        let graph = TaskLedger()
        let nodeA = TaskRecord(
            abstractState: .repoLoaded,
            planningStateID: PlanningStateID(rawValue: "A")
        )
        let nodeB = TaskRecord(
            abstractState: .testsRunning,
            planningStateID: PlanningStateID(rawValue: "B")
        )
        graph.addOrMergeNode(nodeA)
        graph.addOrMergeNode(nodeB)

        let edge = TaskRecordEdge(
            fromNodeID: nodeA.id,
            toNodeID: nodeB.id,
            action: "run_tests"
        )
        graph.addEdge(edge)

        let outgoing = graph.outgoingEdges(from: nodeA.id)
        #expect(outgoing.count == 1)
        #expect(outgoing.first?.action == "run_tests")
    }

    @Test("TaskLedger viable edges exclude failed and abandoned")
    func taskGraphViableEdges() {
        let graph = TaskLedger()
        let nodeA = TaskRecord(
            abstractState: .repoLoaded,
            planningStateID: PlanningStateID(rawValue: "A")
        )
        let nodeB = TaskRecord(
            abstractState: .testsRunning,
            planningStateID: PlanningStateID(rawValue: "B")
        )
        let nodeC = TaskRecord(
            abstractState: .buildRunning,
            planningStateID: PlanningStateID(rawValue: "C")
        )
        graph.addOrMergeNode(nodeA)
        graph.addOrMergeNode(nodeB)
        graph.addOrMergeNode(nodeC)

        let edge1 = TaskRecordEdge(fromNodeID: nodeA.id, toNodeID: nodeB.id, action: "run_tests")
        edge1.recordSuccess()
        let edge2 = TaskRecordEdge(fromNodeID: nodeA.id, toNodeID: nodeC.id, action: "build")
        edge2.recordFailure()

        graph.addEdge(edge1)
        graph.addEdge(edge2)

        let viable = graph.viableEdges(from: nodeA.id)
        #expect(viable.count == 1)
        #expect(viable.first?.action == "run_tests")
    }

    @Test("TaskLedger alternate edges for recovery exclude the failed edge")
    func taskGraphAlternateEdges() {
        let graph = TaskLedger()
        let nodeA = TaskRecord(abstractState: .repoLoaded, planningStateID: PlanningStateID(rawValue: "A"))
        let nodeB = TaskRecord(abstractState: .testsRunning, planningStateID: PlanningStateID(rawValue: "B"))
        let nodeC = TaskRecord(abstractState: .buildRunning, planningStateID: PlanningStateID(rawValue: "C"))
        graph.addOrMergeNode(nodeA)
        graph.addOrMergeNode(nodeB)
        graph.addOrMergeNode(nodeC)

        let edge1 = TaskRecordEdge(id: "e1", fromNodeID: nodeA.id, toNodeID: nodeB.id, action: "run_tests")
        let edge2 = TaskRecordEdge(id: "e2", fromNodeID: nodeA.id, toNodeID: nodeC.id, action: "build")
        graph.addEdge(edge1)
        graph.addEdge(edge2)

        let alternates = graph.alternateEdges(from: nodeA.id, excluding: "e1")
        #expect(alternates.count == 1)
        #expect(alternates.first?.id == "e2")
    }

    @Test("TaskLedger recordExecution advances current node")
    func taskGraphRecordExecution() {
        let graph = TaskLedger()
        let nodeA = TaskRecord(abstractState: .repoLoaded, planningStateID: PlanningStateID(rawValue: "A"))
        let nodeB = TaskRecord(abstractState: .testsRunning, planningStateID: PlanningStateID(rawValue: "B"))
        graph.addOrMergeNode(nodeA)
        graph.setCurrent(nodeA.id)

        let edge = TaskRecordEdge(id: "e1", fromNodeID: nodeA.id, toNodeID: nodeB.id, action: "run_tests")
        graph.addEdge(edge)

        let result = graph.recordExecution(edgeID: "e1", resultNode: nodeB, latencyMs: 150, cost: 1.0)
        #expect(result.abstractState == .testsRunning)
        #expect(graph.currentNodeID == result.id)
        #expect(edge.status == .executedSuccess)
        #expect(edge.successCount == 1)
    }

    @Test("TaskLedger recordFailure does not advance current node")
    func taskGraphRecordFailure() {
        let graph = TaskLedger()
        let nodeA = TaskRecord(abstractState: .repoLoaded, planningStateID: PlanningStateID(rawValue: "A"))
        graph.addOrMergeNode(nodeA)
        graph.setCurrent(nodeA.id)

        let edge = TaskRecordEdge(id: "e1", fromNodeID: nodeA.id, toNodeID: "B", action: "run_tests")
        graph.addEdge(edge)

        graph.recordFailure(edgeID: "e1")
        #expect(graph.currentNodeID == nodeA.id) // Did NOT advance
        #expect(edge.status == .executedFailure)
    }

    // MARK: - StateAbstractor Tests

    @Test("StateAbstractor derives repo_loaded for code state without specific phase")
    func stateAbstractorRepoLoaded() {
        let abstractor = StateAbstractor()
        _ = makePlanningState(id: "code|main", appID: "Xcode", taskPhase: "editing")
        let repo = makeRepoSnapshot()
        let ws = WorldState(
            observation: Observation(app: "Xcode", windowTitle: "Project", url: nil, focusedElementID: nil, elements: []),
            repositorySnapshot: repo
        )
        let state = abstractor.abstractState(from: ws)
        #expect(state == .repoLoaded)
    }

    @Test("StateAbstractor derives tests_running for test phase")
    func stateAbstractorTestsRunning() {
        let abstractor = StateAbstractor()
        let ps = makePlanningState(id: "code|test", taskPhase: "test_running")
        let repo = makeRepoSnapshot()
        let ws = WorldState(
            observationHash: "hash",
            planningState: ps,
            observation: Observation(app: "Xcode", windowTitle: "Tests", url: nil, focusedElementID: nil, elements: []),
            repositorySnapshot: repo
        )
        let state = abstractor.abstractState(from: ws)
        #expect(state == .testsRunning)
    }

    @Test("StateAbstractor derives modal_dialog_active for modal state")
    func stateAbstractorModal() {
        let abstractor = StateAbstractor()
        let ps = makePlanningState(id: "modal", modalClass: "alert")
        let ws = WorldState(
            observationHash: "hash",
            planningState: ps,
            observation: Observation(app: "App", windowTitle: "Alert", url: nil, focusedElementID: nil, elements: [])
        )
        let state = abstractor.abstractState(from: ws)
        #expect(state == .modalDialogActive)
    }

    @Test("StateAbstractor derives permission_dialog_active for permission modal")
    func stateAbstractorPermission() {
        let abstractor = StateAbstractor()
        let ps = makePlanningState(id: "perm", modalClass: "permission_dialog")
        let ws = WorldState(
            observationHash: "hash",
            planningState: ps,
            observation: Observation(app: "App", windowTitle: "Permission", url: nil, focusedElementID: nil, elements: [])
        )
        let state = abstractor.abstractState(from: ws)
        #expect(state == .permissionDialogActive)
    }

    // MARK: - LedgerScorer Tests

    @Test("LedgerScorer scores edge with success probability")
    func graphScorerEdgeScore() {
        let scorer = LedgerScorer()
        let edge = TaskRecordEdge(fromNodeID: "A", toNodeID: "B", action: "test")
        edge.recordSuccess()
        edge.recordSuccess()
        edge.recordFailure()
        // successProbability = 2/3 ≈ 0.667

        let score = scorer.scoreEdge(edge)
        // 0.30 * 0.667 + noveltyBonus(0.0 since attempts == 3) ≈ 0.20
        #expect(score > 0)
    }

    @Test("LedgerScorer gives goal alignment bonus when target matches goal")
    func graphScorerGoalAlignment() {
        let scorer = LedgerScorer()
        let edge = TaskRecordEdge(fromNodeID: "A", toNodeID: "B", action: "test")
        edge.recordSuccess()

        let scoreNoGoal = scorer.scoreEdge(edge)
        let scoreWithGoal = scorer.scoreEdge(
            edge,
            goalState: .testsPassed,
            targetState: .testsPassed
        )
        // Goal-aligned score should be higher
        #expect(scoreWithGoal > scoreNoGoal)
    }

    @Test("LedgerScorer gives partial credit for related states")
    func graphScorerRelatedStates() {
        let scorer = LedgerScorer()
        let edge = TaskRecordEdge(fromNodeID: "A", toNodeID: "B", action: "test")
        edge.recordSuccess()

        let fullMatch = scorer.scoreEdge(
            edge,
            goalState: .testsPassed,
            targetState: .testsPassed
        )
        let relatedMatch = scorer.scoreEdge(
            edge,
            goalState: .testsPassed,
            targetState: .testsRunning
        )
        let noMatch = scorer.scoreEdge(
            edge,
            goalState: .testsPassed,
            targetState: .repoLoaded
        )
        // Full > Related > No match
        #expect(fullMatch > relatedMatch)
        #expect(relatedMatch > noMatch)
    }

    @Test("LedgerScorer goal abstract state derivation from goal description")
    func graphScorerGoalDerivation() {
        #expect(LedgerScorer.goalAbstractState(from: Goal(description: "fix failing tests")) == .testsPassed)
        #expect(LedgerScorer.goalAbstractState(from: Goal(description: "build the project")) == .buildSucceeded)
        #expect(LedgerScorer.goalAbstractState(from: Goal(description: "navigate to settings")) == .navigationCompleted)
        #expect(LedgerScorer.goalAbstractState(from: Goal(description: "something random")) == nil)
    }

    // MARK: - LedgerNavigator Tests

    @Test("LedgerNavigator expands paths from current node")
    func graphNavigatorExpand() {
        let graph = TaskLedger()
        let nodeA = TaskRecord(abstractState: .repoLoaded, planningStateID: PlanningStateID(rawValue: "A"))
        let nodeB = TaskRecord(abstractState: .testsRunning, planningStateID: PlanningStateID(rawValue: "B"))
        let nodeC = TaskRecord(abstractState: .testsPassed, planningStateID: PlanningStateID(rawValue: "C"))
        graph.addOrMergeNode(nodeA)
        graph.addOrMergeNode(nodeB)
        graph.addOrMergeNode(nodeC)

        let edge1 = TaskRecordEdge(fromNodeID: nodeA.id, toNodeID: nodeB.id, action: "run_tests")
        edge1.recordSuccess()
        let edge2 = TaskRecordEdge(fromNodeID: nodeB.id, toNodeID: nodeC.id, action: "verify_tests")
        edge2.recordSuccess()
        graph.addEdge(edge1)
        graph.addEdge(edge2)

        let navigator = LedgerNavigator(maxDepth: 3)
        let scorer = LedgerScorer()
        let paths = navigator.expand(from: nodeA.id, in: graph, scorer: scorer)

        // Should find paths: [A->B] and [A->B->C]
        #expect(paths.count >= 2)
        // Longer path (A->B->C) should have higher cumulative score
        let longestPath = paths.first { $0.edges.count == 2 }
        #expect(longestPath != nil)
    }

    @Test("LedgerNavigator bestNextEdge returns top-scoring first edge")
    func graphNavigatorBestEdge() {
        let graph = TaskLedger()
        let nodeA = TaskRecord(abstractState: .repoLoaded, planningStateID: PlanningStateID(rawValue: "A"))
        let nodeB = TaskRecord(abstractState: .testsRunning, planningStateID: PlanningStateID(rawValue: "B"))
        let nodeC = TaskRecord(abstractState: .buildRunning, planningStateID: PlanningStateID(rawValue: "C"))
        graph.addOrMergeNode(nodeA)
        graph.addOrMergeNode(nodeB)
        graph.addOrMergeNode(nodeC)

        let edge1 = TaskRecordEdge(fromNodeID: nodeA.id, toNodeID: nodeB.id, action: "run_tests")
        edge1.recordSuccess()
        edge1.recordSuccess()
        let edge2 = TaskRecordEdge(fromNodeID: nodeA.id, toNodeID: nodeC.id, action: "build")
        edge2.recordFailure()
        graph.addEdge(edge1)
        graph.addEdge(edge2)

        let navigator = LedgerNavigator()
        let scorer = LedgerScorer()
        let best = navigator.bestNextEdge(from: nodeA.id, in: graph, scorer: scorer)
        // edge1 has 100% success, edge2 has 0% — edge1 should win
        #expect(best?.action == "run_tests")
    }

    @Test("LedgerNavigator avoids cycles in path expansion")
    func graphNavigatorNoCycles() {
        let graph = TaskLedger()
        let nodeA = TaskRecord(abstractState: .repoLoaded, planningStateID: PlanningStateID(rawValue: "A"))
        let nodeB = TaskRecord(abstractState: .testsRunning, planningStateID: PlanningStateID(rawValue: "B"))
        graph.addOrMergeNode(nodeA)
        graph.addOrMergeNode(nodeB)

        // Create cycle: A->B and B->A
        let edgeAB = TaskRecordEdge(fromNodeID: nodeA.id, toNodeID: nodeB.id, action: "forward")
        edgeAB.recordSuccess()
        let edgeBA = TaskRecordEdge(fromNodeID: nodeB.id, toNodeID: nodeA.id, action: "backward")
        edgeBA.recordSuccess()
        graph.addEdge(edgeAB)
        graph.addEdge(edgeBA)

        let navigator = LedgerNavigator(maxDepth: 5)
        let scorer = LedgerScorer()
        let paths = navigator.expand(from: nodeA.id, in: graph, scorer: scorer)

        // Cycle detection should prevent A->B->A. Only A->B (1 edge) should be found.
        for path in paths {
            #expect(path.edges.count <= 1)
        }
    }

    // MARK: - TaskLedgerStore Tests

    @Test("TaskLedgerStore updates current node from world state")
    func taskGraphStoreUpdateCurrent() {
        let store = TaskLedgerStore()
        let ps = makePlanningState(id: "state-1", appID: "Chrome", taskPhase: "browse")
        let ws = WorldState(
            observationHash: "hash1",
            planningState: ps,
            observation: Observation(app: "Chrome", windowTitle: "Browse", url: nil, focusedElementID: nil, elements: [])
        )
        let node = store.updateCurrentNode(worldState: ws)

        #expect(store.currentNode()?.id == node.id)
        #expect(node.abstractState == .pageLoaded)
    }

    @Test("TaskLedgerStore adds candidate edges and records executions")
    func taskGraphStoreEdgeLifecycle() {
        let store = TaskLedgerStore()
        let ps1 = makePlanningState(id: "s1", appID: "App", taskPhase: "browse")
        let ws1 = WorldState(
            observationHash: "h1",
            planningState: ps1,
            observation: Observation(app: "App", windowTitle: "W1", url: nil, focusedElementID: nil, elements: [])
        )
        store.updateCurrentNode(worldState: ws1)

        // Add candidate edge
        let edge = store.addCandidateEdge(
            action: "click_button",
            toAbstractState: .navigationCompleted,
            toPlanningStateID: PlanningStateID(rawValue: "s2")
        )
        #expect(edge != nil)
        #expect(edge?.status == .candidate)

        // Record verified execution
        let ps2 = makePlanningState(id: "s2", appID: "App", taskPhase: "navigate")
        let ws2 = WorldState(
            observationHash: "h2",
            planningState: ps2,
            observation: Observation(app: "App", windowTitle: "W2", url: nil, focusedElementID: nil, elements: [])
        )
        if let edgeID = edge?.id {
            let resultNode = store.recordVerifiedExecution(
                edgeID: edgeID,
                resultWorldState: ws2,
                latencyMs: 200,
                cost: 1.0
            )
            #expect(store.currentNode()?.id == resultNode.id)
        }
    }

    @Test("TaskLedgerStore recovery edges exclude the failed edge")
    func taskGraphStoreRecoveryEdges() {
        let store = TaskLedgerStore()
        let ps = makePlanningState(id: "s1", appID: "App", taskPhase: "browse")
        let ws = WorldState(
            observationHash: "h1",
            planningState: ps,
            observation: Observation(app: "App", windowTitle: "W", url: nil, focusedElementID: nil, elements: [])
        )
        store.updateCurrentNode(worldState: ws)

        let edge1 = store.addCandidateEdge(
            action: "try_A",
            toAbstractState: .navigationCompleted,
            toPlanningStateID: PlanningStateID(rawValue: "s2")
        )
        _ = store.addCandidateEdge(
            action: "try_B",
            toAbstractState: .formVisible,
            toPlanningStateID: PlanningStateID(rawValue: "s3")
        )

        guard let failedID = edge1?.id else {
            Issue.record("edge1 should exist")
            return
        }

        store.recordFailedExecution(edgeID: failedID)
        let recovery = store.recoveryEdges(excludingEdgeID: failedID)
        #expect(recovery.count == 1)
        #expect(recovery.first?.action == "try_B")
    }

    // MARK: - Export Tests

    @Test("TaskLedgerStore exports DOT format")
    func taskGraphStoreExportDOT() {
        let store = TaskLedgerStore()
        let ps = makePlanningState(id: "s1", appID: "App", taskPhase: "browse")
        let ws = WorldState(
            observationHash: "h1",
            planningState: ps,
            observation: Observation(app: "App", windowTitle: "W", url: nil, focusedElementID: nil, elements: [])
        )
        store.updateCurrentNode(worldState: ws)
        store.addCandidateEdge(
            action: "navigate",
            toAbstractState: .navigationCompleted,
            toPlanningStateID: PlanningStateID(rawValue: "s2")
        )

        let dot = store.exportDOT()
        #expect(dot.contains("digraph TaskLedger"))
        #expect(dot.contains("navigate"))
    }

    @Test("TaskLedgerStore exports JSON format")
    func taskGraphStoreExportJSON() {
        let store = TaskLedgerStore()
        let ps = makePlanningState(id: "s1", appID: "App", taskPhase: "browse")
        let ws = WorldState(
            observationHash: "h1",
            planningState: ps,
            observation: Observation(app: "App", windowTitle: "W", url: nil, focusedElementID: nil, elements: [])
        )
        store.updateCurrentNode(worldState: ws)

        let json = store.exportJSON()
        let nodes = json["nodes"] as? [[String: Any]]
        #expect(nodes?.count == 1)
        #expect((json["currentNodeID"] as? String)?.isEmpty == false)
    }

    // MARK: - RecoveryPlanner Graph Integration

    @Test("RecoveryPlanner returns graph recovery edges sorted by success probability")
    func recoveryPlannerGraphEdges() {
        let store = TaskLedgerStore()
        let ps = makePlanningState(id: "s1", appID: "App", taskPhase: "browse")
        let ws = WorldState(
            observationHash: "h1",
            planningState: ps,
            observation: Observation(app: "App", windowTitle: "W", url: nil, focusedElementID: nil, elements: [])
        )
        store.updateCurrentNode(worldState: ws)

        let edge1 = store.addCandidateEdge(
            action: "approach_A",
            toAbstractState: .navigationCompleted,
            toPlanningStateID: PlanningStateID(rawValue: "s2")
        )
        let edge2 = store.addCandidateEdge(
            action: "approach_B",
            toAbstractState: .formVisible,
            toPlanningStateID: PlanningStateID(rawValue: "s3")
        )

        // Give edge2 some success evidence
        edge2?.recordSuccess()
        edge2?.recordSuccess()

        guard let failedID = edge1?.id else {
            Issue.record("edge1 should exist")
            return
        }

        let planner = MainPlanner()
        let recoveryEdges = planner.graphRecoveryEdges(
            failedEdgeID: failedID,
            taskGraphStore: store
        )
        #expect(recoveryEdges.count == 1)
        #expect(recoveryEdges.first?.action == "approach_B")
    }

    // MARK: - Full Cycle Test

    @Test("Full task-graph cycle: observe → abstract → expand → execute → update")
    func fullTaskGraphCycle() {
        let store = TaskLedgerStore()

        // Step 1: Observe environment → create initial node
        let ps1 = makePlanningState(id: "s1", appID: "Xcode", taskPhase: "editing")
        let repo = makeRepoSnapshot()
        let ws1 = WorldState(
            observationHash: "h1",
            planningState: ps1,
            observation: Observation(app: "Xcode", windowTitle: "Editor", url: nil, focusedElementID: nil, elements: []),
            repositorySnapshot: repo
        )
        let startNode = store.updateCurrentNode(worldState: ws1)
        #expect(startNode.abstractState == .repoLoaded)

        // Step 2: Add candidate edges (planner would do this)
        _ = store.addCandidateEdge(
            action: "run_tests",
            actionContractID: "run-tests-contract",
            toAbstractState: .testsRunning,
            toPlanningStateID: PlanningStateID(rawValue: "s2")
        )
        _ = store.addCandidateEdge(
            action: "build",
            actionContractID: "build-contract",
            toAbstractState: .buildRunning,
            toPlanningStateID: PlanningStateID(rawValue: "s3")
        )

        // Step 3: Navigate and select best edge
        let navigator = LedgerNavigator()
        let scorer = LedgerScorer()
        let paths = navigator.expand(
            from: startNode.id,
            in: store.graph,
            scorer: scorer,
            goal: Goal(description: "fix failing tests")
        )
        #expect(!paths.isEmpty)

        // Step 4: Execute best edge (simulated)
        guard let chosenEdge = paths.first?.edges.first else {
            Issue.record("Should have at least one path")
            return
        }

        // Step 5: Record successful execution
        let ps2 = makePlanningState(id: "s2", appID: "Xcode", taskPhase: "test_running")
        let ws2 = WorldState(
            observationHash: "h2",
            planningState: ps2,
            observation: Observation(app: "Xcode", windowTitle: "Tests", url: nil, focusedElementID: nil, elements: []),
            repositorySnapshot: repo
        )
        let resultNode = store.recordVerifiedExecution(
            edgeID: chosenEdge.id,
            resultWorldState: ws2,
            latencyMs: 500,
            cost: 2.0
        )

        // Step 6: Verify graph state
        #expect(store.currentNode()?.id == resultNode.id)
        #expect(store.graph.nodeCount >= 2)
        #expect(store.graph.edgeCount >= 2)
    }
}
