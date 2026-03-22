import Foundation
import Testing
@testable import OracleOS

@Suite("Prompt Engine")
struct PromptEngineTests {

    @Test("Prompt builder renders the required sections")
    func promptBuilderRendersRequiredSections() {
        let context = PromptContext(
            templateKind: .codeRepair,
            goal: "Fix the failing test suite",
            context: ["Repository root: /tmp/workspace"],
            state: ["3 tests failing"],
            constraints: ["Do not modify tests"],
            availableActions: ["run_tests(scope)", "apply_patch(targets)"],
            relevantKnowledge: ["Likely target: Sources/Example/Calculator.swift"],
            expectedOutput: ["One bounded engineering action"],
            evaluationCriteria: ["Prefer the smallest viable patch surface"]
        )

        let document = PromptBuilder().build(from: context)

        #expect(document.rendered.contains("GOAL:"))
        #expect(document.rendered.contains("CONTEXT:"))
        #expect(document.rendered.contains("CURRENT STATE:"))
        #expect(document.rendered.contains("CONSTRAINTS:"))
        #expect(document.rendered.contains("AVAILABLE ACTIONS:"))
        #expect(document.rendered.contains("RELEVANT KNOWLEDGE:"))
        #expect(document.rendered.contains("EXPECTED OUTPUT:"))
        #expect(document.rendered.contains("EVALUATION CRITERIA:"))
    }

    @Test("Prompt engine caches repeated prompt builds")
    func promptEngineCachesRepeatedPromptBuilds() {
        let cache = PromptCache()
        let engine = PromptEngine(cache: cache)
        let taskContext = TaskContext.from(
            goal: Goal(
                description: "fix calculator build failure",
                workspaceRoot: "/tmp/workspace",
                preferredAgentKind: .code
            ),
            workspaceRoot: URL(fileURLWithPath: "/tmp/workspace", isDirectory: true)
        )
        let snapshot = RepositorySnapshot(
            id: "repo",
            workspaceRoot: "/tmp/workspace",
            buildTool: .swiftPackage,
            files: [RepositoryFile(path: "Sources/Example/Calculator.swift", isDirectory: false)],
            symbolGraph: SymbolGraph(),
            dependencyGraph: DependencyGraph(),
            testGraph: TestGraph(),
            activeBranch: "main",
            isGitDirty: true
        )
        let worldState = WorldState(
            observation: Observation(app: "Workspace", windowTitle: "Workspace", url: nil, focusedElementID: nil, elements: []),
            repositorySnapshot: snapshot
        )

        let first = engine.codeRepair(
            taskContext: taskContext,
            worldState: worldState,
            snapshot: snapshot,
            candidatePaths: ["Sources/Example/Calculator.swift"],
            projectMemoryRefs: [],
            architectureFindings: [],
            notes: ["bounded repair"],
            executionMode: .direct
        )
        let second = engine.codeRepair(
            taskContext: taskContext,
            worldState: worldState,
            snapshot: snapshot,
            candidatePaths: ["Sources/Example/Calculator.swift"],
            projectMemoryRefs: [],
            architectureFindings: [],
            notes: ["bounded repair"],
            executionMode: .direct
        )

        #expect(first.diagnostics.cacheHit == false)
        #expect(second.diagnostics.cacheHit == true)
        #expect(first.document.rendered == second.document.rendered)
    }
}
