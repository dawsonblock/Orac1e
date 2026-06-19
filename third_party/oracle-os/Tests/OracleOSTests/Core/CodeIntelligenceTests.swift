import Foundation
import Testing
@testable import OracleOS

@Suite("Code Intelligence")
struct CodeIntelligenceTests {
    @Test("Repository indexer builds structural graphs and persists snapshot")
    func repositoryIndexerBuildsStructuralGraphsAndPersistsSnapshot() throws {
        let workspace = try makeRepositoryWorkspace()

        let snapshot = RepositoryIndexer().index(workspaceRoot: workspace)

        #expect(snapshot.symbolGraph.nodes.contains(where: { $0.name == "Calculator" }))
        #expect(snapshot.symbolGraph.nodes.contains(where: { $0.name == "helper" }))
        #expect(snapshot.callGraph.edges.isEmpty == false)
        #expect(snapshot.testGraph.tests.contains(where: { $0.path == "Tests/ExampleTests/CalculatorTests.swift" }))
        #expect(snapshot.testGraph.edges.isEmpty == false)
        #expect(snapshot.buildGraph.targets.contains(where: { $0.name == "Example" }))
        #expect(snapshot.indexDiagnostics.fileCount >= 4)
        #expect(snapshot.indexDiagnostics.symbolCount >= 4)
        #expect(FileManager.default.fileExists(atPath: workspace.appendingPathComponent(".oracle/repo_index.json").path))
    }

    @Test("Code query engine traces a failing test back to likely source")
    func codeQueryEngineTracesFailingTestBackToSource() throws {
        let workspace = try makeRepositoryWorkspace()
        let snapshot = RepositoryIndexer().index(workspaceRoot: workspace)
        let ranked = CodeQueryEngine().findLikelyRootCause(
            failureDescription: "testCalculatorDouble failed with an unexpected result",
            in: snapshot
        )

        #expect(ranked.first?.path == "Sources/Example/Calculator.swift")
    }

    @Test("Root cause analyzer ranks source file above tests and unrelated files")
    func rootCauseAnalyzerRanksSourceAboveTestsAndUnrelatedFiles() throws {
        let workspace = try makeRepositoryWorkspace()
        let snapshot = RepositoryIndexer().index(workspaceRoot: workspace)
        let ranked = RootCauseAnalyzer().analyze(
            failureDescription: "AssertionError: testCalculatorDouble failed in helper with an unexpected result",
            in: snapshot
        )

        #expect(ranked.first?.path == "Sources/Example/Calculator.swift")
        #expect(ranked.first?.matchedSymbols.contains("helper") == true)
        #expect(ranked.first?.reasons.contains(where: { $0.contains("matched test") }) == true)
    }

    @Test("Change impact analyzer reports affected tests and build targets")
    func changeImpactAnalyzerReportsAffectedTestsAndTargets() throws {
        let workspace = try makeRepositoryWorkspace()
        let snapshot = RepositoryIndexer().index(workspaceRoot: workspace)
        let impact = RepositoryChangeImpactAnalyzer().impact(
            of: "Sources/Example/Calculator.swift",
            in: snapshot
        )

        #expect(impact.affectedTests.contains(where: { $0.path == "Tests/ExampleTests/CalculatorTests.swift" }))
        #expect(impact.buildTargets.contains(where: { $0.name == "Example" }))
        #expect(impact.blastRadiusScore > 0)
    }

    @Test("Code planner uses repository intelligence to narrow experiment candidates")
    func codePlannerUsesRepositoryIntelligenceToNarrowExperimentCandidates() throws {
        let workspace = try makeRepositoryWorkspace()
        let planner = CodePlanner()
        let graphStore = GraphStore(databaseURL: makeTempGraphURL())
        let memoryStore = UnifiedMemoryStore()
        let snapshot = RepositoryIndexer().index(workspaceRoot: workspace)

        let candidates = [
            CandidatePatch(
                id: "source-fix",
                title: "Fix source",
                summary: "Repair Calculator.swift directly.",
                workspaceRelativePath: "Sources/Example/Calculator.swift",
                content: "public struct Calculator {\n    public func double(_ value: Int) -> Int { helper(value) }\n}\n\nfunc helper(_ value: Int) -> Int {\n    value * 2\n}\n"
            ),
            CandidatePatch(
                id: "test-fix",
                title: "Patch test",
                summary: "Change the expectation in the test.",
                workspaceRelativePath: "Tests/ExampleTests/CalculatorTests.swift",
                content: "import Example\n\nfunc testCalculatorDouble() {\n    let calculator = Calculator()\n    #expect(calculator.double(2) == 3)\n}\n"
            ),
            CandidatePatch(
                id: "unrelated",
                title: "Touch unrelated utility",
                summary: "Edit an unrelated file.",
                workspaceRelativePath: "Sources/Example/Formatting.swift",
                content: "struct Formatting {\n    static func display(_ value: Int) -> String { \"\\(value)\" }\n}\n"
            ),
        ]

        let taskContext = TaskContext.from(
            goal: Goal(
                description: "compare fixes for testCalculatorDouble failure",
                workspaceRoot: workspace.path,
                preferredAgentKind: .code,
                experimentCandidates: candidates
            ),
            workspaceRoot: workspace
        )
        let worldState = WorldState(
            observation: Observation(app: "Workspace", windowTitle: "Workspace", url: nil, focusedElementID: nil, elements: []),
            repositorySnapshot: snapshot
        )

        let decision = planner.nextStep(
            taskContext: taskContext,
            worldState: worldState,
            graphStore: graphStore,
            memoryStore: memoryStore
        )

        #expect(decision?.executionMode == .experiment)
        #expect(decision?.experimentSpec?.candidates.first?.workspaceRelativePath == "Sources/Example/Calculator.swift")
        #expect(decision?.experimentSpec?.candidates.contains(where: { $0.workspaceRelativePath == "Sources/Example/Formatting.swift" }) == false)
    }

    @Test("Repository indexer reuses persisted snapshot until repository changes")
    func repositoryIndexerReusesPersistedSnapshotUntilRepositoryChanges() throws {
        let workspace = try makeRepositoryWorkspace()
        let indexer = RepositoryIndexer()

        let first = indexer.index(workspaceRoot: workspace)
        let reused = indexer.indexIfNeeded(workspaceRoot: workspace)
        #expect(abs(reused.indexedAt.timeIntervalSince(first.indexedAt)) < 1)
        #expect(reused.symbolGraph == first.symbolGraph)

        let updatedFile = workspace.appendingPathComponent("Sources/Example/NewFeature.swift")
        try """
        struct NewFeature {
            func value() -> Int { 1 }
        }
        """.write(to: updatedFile, atomically: true, encoding: .utf8)

        let reindexed = indexer.indexIfNeeded(workspaceRoot: workspace)
        #expect(reindexed.indexedAt >= first.indexedAt)
        #expect(reindexed.symbolGraph.nodes.contains(where: { $0.name == "NewFeature" }))
    }

    @Test("Runtime diagnostics builder surfaces persisted repository indexes")
    func runtimeDiagnosticsBuilderSurfacesPersistedRepositoryIndexes() throws {
        let workspace = try makeRepositoryWorkspace()
        let snapshot = RepositoryIndexer().index(workspaceRoot: workspace)
        let graphStore = GraphStore(databaseURL: makeTempGraphURL())
        let diagnostics = RuntimeDiagnosticsBuilder().build(
            graphStore: graphStore,
            traceEvents: [
                TraceEvent(
                    sessionID: "session",
                    taskID: nil,
                    stepID: 1,
                    toolName: "run_tests",
                    actionName: "run_tests",
                    verified: true,
                    success: true,
                    repositorySnapshotID: snapshot.id,
                    elapsedMs: 12
                )
            ]
        )

        #expect(diagnostics.repositoryIndexes.count == 1)
        #expect(diagnostics.repositoryIndexes.first?.workspaceRoot == workspace.path)
        #expect(diagnostics.repositoryIndexes.first?.symbolCount == snapshot.symbolGraph.nodes.count)
    }

    private func makeRepositoryWorkspace() throws -> URL {
        let root = makeTempDirectory()
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources/Example", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Tests/ExampleTests", isDirectory: true),
            withIntermediateDirectories: true
        )

        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "Example",
            products: [.library(name: "Example", targets: ["Example"])],
            targets: [
                .target(name: "Example"),
                .testTarget(name: "ExampleTests", dependencies: ["Example"]),
            ]
        )
        """.write(
            to: root.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )

        try """
        public struct Calculator {
            public init() {}

            public func double(_ value: Int) -> Int {
                helper(value)
            }
        }

        func helper(_ value: Int) -> Int {
            value * 2
        }
        """.write(
            to: root.appendingPathComponent("Sources/Example/Calculator.swift"),
            atomically: true,
            encoding: .utf8
        )

        try """
        import Example

        public struct Consumer {
            public init() {}

            public func use(_ value: Int) -> Int {
                Calculator().double(value)
            }
        }
        """.write(
            to: root.appendingPathComponent("Sources/Example/Consumer.swift"),
            atomically: true,
            encoding: .utf8
        )

        try """
        struct Formatting {
            static func display(_ value: Int) -> String {
                "\\(value)"
            }
        }
        """.write(
            to: root.appendingPathComponent("Sources/Example/Formatting.swift"),
            atomically: true,
            encoding: .utf8
        )

        try """
        import Example

        func testCalculatorDouble() {
            let calculator = Calculator()
            #expect(calculator.double(2) == 4)
        }
        """.write(
            to: root.appendingPathComponent("Tests/ExampleTests/CalculatorTests.swift"),
            atomically: true,
            encoding: .utf8
        )

        return root
    }

    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeTempGraphURL() -> URL {
        makeTempDirectory().appendingPathComponent("graph.sqlite", isDirectory: false)
    }
}
