import Foundation
import Testing
@testable import OracleOS

@Suite("Search — SearchController")
struct SearchControllerTests {

    @Test("Search returns nil when no candidates exist")
    @MainActor func noCandidatesReturnsNil() {
        let controller = makeController()
        let state = CompressedUIState(app: "App", elements: [])
        let result = controller.search(
            compressedState: state,
            abstractState: .idle
        ) { _ in nil }
        #expect(result == nil)
    }

    @Test("Search returns best successful candidate")
    @MainActor func returnsBestSuccessful() {
        let index = StateMemoryIndex()
        let store = GraphStore()
        let state = CompressedUIState(
            app: "App",
            elements: [SemanticElement(id: "b", kind: .button, label: "Go")]
        )
        index.record(state: state, actionName: "click_Go", success: true)

        let controller = SearchController(
            generator: CandidateGenerator(
                stateMemoryIndex: index,
                planningGraphStore: store
            )
        )

        let result = controller.search(
            compressedState: state,
            abstractState: .taskStarted
        ) { candidate in
            CandidateResult(
                candidate: candidate,
                success: true,
                score: 1.0,
                criticOutcome: .success,
                elapsedMs: 50
            )
        }

        #expect(result != nil)
        #expect(result?.success == true)
        #expect(result?.candidate.schema.name == "click_Go")
    }

    @Test("Search early-exits on successful memory candidate")
    @MainActor func earlyExitOnMemorySuccess() {
        let index = StateMemoryIndex()
        let store = GraphStore()
        let state = CompressedUIState(
            app: "App",
            elements: [SemanticElement(id: "b", kind: .button, label: "Save")]
        )
        index.record(state: state, actionName: "click_Save", success: true)

        // Add a graph candidate that would be evaluated second.
        store.addEdge(PlanningEdge(
            fromState: .taskStarted,
            toState: .taskCompleted,
            schema: ActionSchema(name: "other_action", kind: .custom)
        ))

        let controller = SearchController(
            generator: CandidateGenerator(
                stateMemoryIndex: index,
                planningGraphStore: store
            )
        )

        var evaluatedCount = 0
        _ = controller.search(
            compressedState: state,
            abstractState: .taskStarted
        ) { candidate in
            evaluatedCount += 1
            return CandidateResult(
                candidate: candidate,
                success: true,
                score: 1.0,
                criticOutcome: .success,
                elapsedMs: 50
            )
        }

        // Should early-exit after the memory candidate succeeds.
        #expect(evaluatedCount == 1)
    }

    @Test("Search evaluates all candidates when memory fails")
    @MainActor func evaluatesAllWhenMemoryFails() {
        let index = StateMemoryIndex()
        let store = GraphStore()
        let state = CompressedUIState(
            app: "App",
            elements: [SemanticElement(id: "b", kind: .button, label: "Try")]
        )
        index.record(state: state, actionName: "click_Try", success: true)

        store.addEdge(PlanningEdge(
            fromState: .taskStarted,
            toState: .taskCompleted,
            schema: ActionSchema(name: "graph_action", kind: .custom)
        ))

        let controller = SearchController(
            generator: CandidateGenerator(
                stateMemoryIndex: index,
                planningGraphStore: store
            )
        )

        var evaluatedCount = 0
        let result = controller.search(
            compressedState: state,
            abstractState: .taskStarted
        ) { candidate in
            evaluatedCount += 1
            // First candidate (memory) fails, second (graph) succeeds.
            let isSuccess = candidate.source == .graph
            return CandidateResult(
                candidate: candidate,
                success: isSuccess,
                score: isSuccess ? 1.0 : 0.0,
                criticOutcome: isSuccess ? .success : .failure,
                elapsedMs: 50
            )
        }

        #expect(evaluatedCount == controller.maxCandidates)
        #expect(result?.success == true)
        #expect(result?.candidate.source == .graph)
    }

    // MARK: - Helpers

    @MainActor
    private func makeController() -> SearchController {
        SearchController(
            generator: CandidateGenerator(
                stateMemoryIndex: StateMemoryIndex(),
                planningGraphStore: GraphStore()
            )
        )
    }
}
