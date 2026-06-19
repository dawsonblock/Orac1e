import Foundation
import Testing
@testable import OracleOS

@Suite("Search — CandidateGenerator")
struct CandidateGeneratorTests {

    // MARK: - Memory-first priority

    @Test("Memory candidates appear before graph candidates")
    @MainActor func memoryBeforeGraph() {
        let index = StateMemoryIndex()
        let store = GraphStore()
        let state = CompressedUIState(
            app: "Finder",
            elements: [SemanticElement(id: "btn", kind: .button, label: "Open")]
        )
        // Seed memory with a known action.
        index.record(state: state, actionName: "click_Open", success: true)

        // Seed graph with a different action.
        store.addEdge(PlanningEdge(
            fromState: .taskStarted,
            toState: .taskCompleted,
            schema: ActionSchema(name: "navigate_home", kind: .navigate)
        ))

        let generator = CandidateGenerator(
            stateMemoryIndex: index,
            planningGraphStore: store
        )
        let candidates = generator.generate(
            compressedState: state,
            abstractState: .taskStarted
        )

        #expect(candidates.count >= 2)
        #expect(candidates[0].source == .memory)
        #expect(candidates[0].schema.name == "click_Open")
        #expect(candidates[1].source == .graph)
    }

    @Test("LLM candidates are last and fill gaps only")
    @MainActor func llmCandidatesAreLast() {
        let index = StateMemoryIndex()
        let store = GraphStore()
        let state = CompressedUIState(app: "Safari", elements: [])

        let llmSchemas = [
            ActionSchema(name: "llm_action", kind: .custom),
        ]

        let generator = CandidateGenerator(
            stateMemoryIndex: index,
            planningGraphStore: store
        )
        let candidates = generator.generate(
            compressedState: state,
            abstractState: .idle,
            llmSchemas: llmSchemas
        )

        #expect(candidates.count == 1)
        #expect(candidates[0].source == .llmFallback)
    }

    @Test("Duplicate action names are deduplicated across sources")
    @MainActor func deduplicatesAcrossSources() {
        let index = StateMemoryIndex()
        let store = GraphStore()
        let state = CompressedUIState(
            app: "Xcode",
            elements: [SemanticElement(id: "b", kind: .button, label: "Build")]
        )

        // Same action in memory and graph.
        index.record(state: state, actionName: "build_project", success: true)
        store.addEdge(PlanningEdge(
            fromState: .repoLoaded,
            toState: .buildRunning,
            schema: ActionSchema(name: "build_project", kind: .buildProject)
        ))

        let generator = CandidateGenerator(
            stateMemoryIndex: index,
            planningGraphStore: store
        )
        let candidates = generator.generate(
            compressedState: state,
            abstractState: .repoLoaded
        )

        let names = candidates.map(\.schema.name)
        // "build_project" should appear only once (from memory).
        #expect(names.filter { $0 == "build_project" }.count == 1)
        #expect(candidates.first?.source == .memory)
    }

    @Test("maxCandidates caps the output")
    @MainActor func maxCandidatesCaps() {
        let index = StateMemoryIndex()
        let store = GraphStore()
        let state = CompressedUIState(app: "App", elements: [])

        // Add many LLM schemas.
        let llmSchemas = (0..<10).map {
            ActionSchema(name: "action_\($0)", kind: .custom)
        }

        let generator = CandidateGenerator(
            stateMemoryIndex: index,
            planningGraphStore: store,
            maxCandidates: 3
        )
        let candidates = generator.generate(
            compressedState: state,
            abstractState: .idle,
            llmSchemas: llmSchemas
        )

        #expect(candidates.count == 3)
    }

    @Test("Empty state produces no candidates without LLM")
    @MainActor func emptyStateNoLLM() {
        let index = StateMemoryIndex()
        let store = GraphStore()
        let state = CompressedUIState(app: "Empty", elements: [])

        let generator = CandidateGenerator(
            stateMemoryIndex: index,
            planningGraphStore: store
        )
        let candidates = generator.generate(
            compressedState: state,
            abstractState: .idle
        )

        #expect(candidates.isEmpty)
    }
}
