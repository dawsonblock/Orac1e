import Foundation
import Testing
@testable import OracleOS

@Suite("Planning Graph Engine")
struct PlanningGraphEngineTests {

    // MARK: - Edge scoring

    @Test("New edge has default score of 0.5")
    func newEdgeDefaultScore() {
        let edge = PlanningEdge(
            fromState: .repoLoaded,
            toState: .testsRunning,
            schema: ActionSchema(name: "run_tests", kind: .runTests)
        )
        #expect(edge.successRate == 0.5)
        #expect(edge.attempts == 0)
        #expect(edge.score == 0.5)
    }

    @Test("Recording success increases success rate")
    func recordSuccessIncreasesRate() {
        var edge = PlanningEdge(
            fromState: .repoLoaded,
            toState: .testsRunning,
            schema: ActionSchema(name: "run_tests", kind: .runTests),
            successRate: 0,
            attempts: 0,
            successes: 0
        )
        edge.recordSuccess(latencyMs: 100)
        #expect(edge.successes == 1)
        #expect(edge.attempts == 1)
        #expect(edge.successRate == 1.0)
    }

    @Test("Recording failure decreases success rate")
    func recordFailureDecreasesRate() {
        var edge = PlanningEdge(
            fromState: .repoLoaded,
            toState: .build_failed,
            schema: ActionSchema(name: "build_project", kind: .buildProject),
            successRate: 1.0,
            attempts: 1,
            successes: 1
        )
        edge.recordFailure(latencyMs: 200)
        #expect(edge.successes == 1)
        #expect(edge.attempts == 2)
        #expect(edge.successRate == 0.5)
    }

    // MARK: - Graph queries

    @Test("candidateEdges returns edges sorted by score")
    func candidateEdgesSortedByScore() {
        let good = PlanningEdge(
            fromState: .repoLoaded,
            toState: .testsRunning,
            schema: ActionSchema(name: "run_tests", kind: .runTests),
            successRate: 0.9,
            attempts: 10,
            successes: 9
        )
        let poor = PlanningEdge(
            fromState: .repoLoaded,
            toState: .build_failed,
            schema: ActionSchema(name: "build", kind: .buildProject),
            successRate: 0.3,
            attempts: 10,
            successes: 3
        )
        let engine = PlanningGraphEngine(edges: [poor, good])
        let candidates = engine.candidateEdges(from: .repoLoaded)
        #expect(candidates.count == 2)
        #expect(candidates[0].schema.name == "run_tests")
        #expect(candidates[1].schema.name == "build")
    }

    @Test("bestEdge returns highest scoring edge")
    func bestEdgeReturnsHighest() {
        let edge = PlanningEdge(
            fromState: .repoLoaded,
            toState: .testsRunning,
            schema: ActionSchema(name: "run_tests", kind: .runTests),
            successRate: 0.9
        )
        let engine = PlanningGraphEngine(edges: [edge])
        let best = engine.bestEdge(from: .repoLoaded)
        #expect(best?.schema.name == "run_tests")
    }

    @Test("bestEdge returns nil for unknown state")
    func bestEdgeNilForUnknownState() {
        let engine = PlanningGraphEngine(edges: [])
        #expect(engine.bestEdge(from: .idle) == nil)
    }

    // MARK: - Mutation

    @Test("addEdge increases edge count")
    func addEdgeIncreasesCount() {
        var engine = PlanningGraphEngine()
        #expect(engine.edgeCount == 0)
        engine.addEdge(PlanningEdge(
            fromState: .idle,
            toState: .repoLoaded,
            schema: ActionSchema(name: "load", kind: .custom)
        ))
        #expect(engine.edgeCount == 1)
    }

    @Test("recordOutcome updates existing edge stats")
    func recordOutcomeUpdatesEdge() {
        let edge = PlanningEdge(
            id: "e1",
            fromState: .repoLoaded,
            toState: .testsRunning,
            schema: ActionSchema(name: "run_tests", kind: .runTests),
            successRate: 0,
            attempts: 0,
            successes: 0
        )
        var engine = PlanningGraphEngine(edges: [edge])
        engine.recordOutcome(edgeID: "e1", success: true, latencyMs: 50)
        let candidates = engine.candidateEdges(from: .repoLoaded)
        #expect(candidates.first?.attempts == 1)
        #expect(candidates.first?.successes == 1)
    }

    @Test("pruneWeakEdges removes low-success edges")
    func pruneWeakEdges() {
        let weak = PlanningEdge(
            fromState: .repoLoaded,
            toState: .build_failed,
            schema: ActionSchema(name: "bad", kind: .custom),
            successRate: 0.05,
            attempts: 10,
            successes: 0
        )
        let strong = PlanningEdge(
            fromState: .repoLoaded,
            toState: .testsRunning,
            schema: ActionSchema(name: "good", kind: .runTests),
            successRate: 0.9,
            attempts: 10,
            successes: 9
        )
        var engine = PlanningGraphEngine(edges: [weak, strong])
        engine.pruneWeakEdges(belowRate: 0.1, minAttempts: 5)
        let candidates = engine.candidateEdges(from: .repoLoaded)
        #expect(candidates.count == 1)
        #expect(candidates[0].schema.name == "good")
    }

    // MARK: - allStates

    @Test("allStates includes both source and destination states")
    func allStatesIncludesBothEnds() {
        let edge = PlanningEdge(
            fromState: .idle,
            toState: .repoLoaded,
            schema: ActionSchema(name: "load", kind: .custom)
        )
        let engine = PlanningGraphEngine(edges: [edge])
        let states = engine.allStates
        #expect(states.contains(.idle))
        #expect(states.contains(.repoLoaded))
    }

    // MARK: - recordOutcome by state + schema

    @Test("recordOutcome by state creates new edge when none exists")
    func recordOutcomeByStateCreatesEdge() {
        var engine = PlanningGraphEngine()
        let schema = ActionSchema(name: "run_tests", kind: .runTests)
        engine.recordOutcome(
            fromState: "repo_loaded",
            toState: "tests_running",
            schema: schema,
            success: true
        )
        let candidates = engine.candidateEdges(from: .repoLoaded)
        #expect(candidates.count == 1)
        #expect(candidates.first?.schema.name == "run_tests")
        #expect(candidates.first?.successes == 1)
        #expect(candidates.first?.attempts == 1)
    }

    @Test("recordOutcome by state updates existing edge")
    func recordOutcomeByStateUpdatesExisting() {
        var engine = PlanningGraphEngine()
        let schema = ActionSchema(name: "build", kind: .buildProject)
        engine.recordOutcome(
            fromState: "repo_loaded",
            toState: "build_succeeded",
            schema: schema,
            success: true
        )
        engine.recordOutcome(
            fromState: "repo_loaded",
            toState: "build_succeeded",
            schema: schema,
            success: false
        )
        let candidates = engine.candidateEdges(from: .repoLoaded)
        #expect(candidates.count == 1)
        #expect(candidates.first?.attempts == 2)
        #expect(candidates.first?.successes == 1)
    }

    @Test("recordOutcome by state ignores invalid raw values")
    func recordOutcomeByStateIgnoresInvalid() {
        var engine = PlanningGraphEngine()
        let schema = ActionSchema(name: "test", kind: .custom)
        engine.recordOutcome(
            fromState: "not_a_real_state",
            toState: "also_invalid",
            schema: schema,
            success: true
        )
        #expect(engine.edgeCount == 0)
    }

    // MARK: - validActions

    @Test("validActions returns schemas for edges from a state")
    func validActionsReturnsSchemas() {
        let schema1 = ActionSchema(name: "run_tests", kind: .runTests)
        let schema2 = ActionSchema(name: "build_project", kind: .buildProject)
        let edge1 = PlanningEdge(
            fromState: .repoLoaded,
            toState: .testsRunning,
            schema: schema1
        )
        let edge2 = PlanningEdge(
            fromState: .repoLoaded,
            toState: .buildRunning,
            schema: schema2
        )
        let engine = PlanningGraphEngine(edges: [edge1, edge2])
        let actions = engine.validActions(for: .repoLoaded)
        let names = actions.map(\.name)
        #expect(actions.count == 2)
        #expect(names.contains("run_tests"))
        #expect(names.contains("build_project"))
    }

    @Test("validActions returns empty for state with no edges")
    func validActionsEmptyForNoEdges() {
        let engine = PlanningGraphEngine()
        let actions = engine.validActions(for: .idle)
        #expect(actions.isEmpty)
    }

    @Test("validActions are sorted by edge score")
    func validActionsSortedByScore() {
        let good = PlanningEdge(
            fromState: .repoLoaded,
            toState: .testsPassed,
            schema: ActionSchema(name: "run_tests", kind: .runTests),
            successRate: 0.9,
            attempts: 10,
            successes: 9
        )
        let poor = PlanningEdge(
            fromState: .repoLoaded,
            toState: .buildFailed,
            schema: ActionSchema(name: "build", kind: .buildProject),
            successRate: 0.2,
            attempts: 10,
            successes: 2
        )
        let engine = PlanningGraphEngine(edges: [poor, good])
        let actions = engine.validActions(for: .repoLoaded)
        #expect(actions.first?.name == "run_tests")
    }
}
