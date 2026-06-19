import Foundation
import Testing
@testable import OracleOS

@Suite("Program Knowledge Graph")
struct ProgramKnowledgeGraphTests {

    // MARK: - Symbol queries

    @Test("Finds symbols by name")
    func findsSymbolsByName() {
        let graph = makeGraph()

        let results = graph.symbols(named: "Calculator")
        #expect(!results.isEmpty)
        #expect(results.first?.name == "Calculator")
    }

    @Test("Finds symbols in file")
    func findsSymbolsInFile() {
        let graph = makeGraph()

        let results = graph.symbols(inFile: "Sources/Calculator.swift")
        #expect(results.count == 2) // Calculator + helper
    }

    @Test("Finds symbol by ID")
    func findsSymbolByID() {
        let graph = makeGraph()

        let result = graph.symbol(id: "calc-class")
        #expect(result?.name == "Calculator")
    }

    // MARK: - Call-graph queries

    @Test("Finds callers of a symbol")
    func findCallersOfSymbol() {
        let graph = makeGraph()

        let callers = graph.callers(of: "helper-fn")
        #expect(callers.contains(where: { $0.name == "Calculator" }))
    }

    @Test("Finds callees of a symbol")
    func findCalleesOfSymbol() {
        let graph = makeGraph()

        let callees = graph.callees(of: "calc-class")
        #expect(callees.contains(where: { $0.name == "helper" }))
    }

    @Test("Call neighborhood expands outward")
    func callNeighborhoodExpands() {
        let graph = makeGraph()

        let neighborhood = graph.callNeighborhood(of: "helper-fn", depth: 1)
        #expect(neighborhood.contains("calc-class"))
    }

    // MARK: - Test coverage queries

    @Test("Finds tests covering a symbol")
    func findsTestsCoveringSymbol() {
        let graph = makeGraph()

        let tests = graph.tests(covering: "calc-class")
        #expect(!tests.isEmpty)
        #expect(tests.first?.name == "testCalculator")
    }

    @Test("Finds tests covering a file")
    func findsTestsCoveringFile() {
        let graph = makeGraph()

        let tests = graph.tests(coveringFile: "Sources/Calculator.swift")
        #expect(!tests.isEmpty)
    }

    @Test("Finds targets of a test")
    func findsTargetsOfTest() {
        let graph = makeGraph()

        let targets = graph.targets(of: "test-calc")
        #expect(!targets.isEmpty)
        #expect(targets.first?.name == "Calculator")
    }

    // MARK: - Dependency queries

    @Test("Finds direct dependencies of a file")
    func findsDirectDependencies() {
        let graph = makeGraph()

        let deps = graph.dependencies(of: "Sources/Consumer.swift")
        #expect(deps.contains("Sources/Calculator.swift"))
    }

    @Test("Finds dependents (reverse dependencies) of a file")
    func findsDependentsOfFile() {
        let graph = makeGraph()

        let dependents = graph.dependents(of: "Sources/Calculator.swift")
        #expect(dependents.contains("Sources/Consumer.swift"))
    }

    // MARK: - Build queries

    @Test("Finds build targets containing a file")
    func findsBuildTargetsContainingFile() {
        let graph = makeGraph()

        let targets = graph.buildTargets(containing: "Sources/Calculator.swift")
        #expect(!targets.isEmpty)
        #expect(targets.first?.name == "MainTarget")
    }

    // MARK: - Composite queries

    @Test("Trace failure from test to source candidates")
    func traceFailureFromTestToSource() {
        let graph = makeGraph()

        let results = graph.traceFailure(testSymbolID: "test-calc")
        #expect(!results.isEmpty)
        #expect(results.first?.filePath == "Sources/Calculator.swift")
        #expect(results.first?.matchedSymbols.contains("Calculator") == true)
    }

    @Test("Trace failure excludes test files from results")
    func traceFailureExcludesTestFiles() {
        let graph = makeGraph()

        let results = graph.traceFailure(testSymbolID: "test-calc")
        let hasTestFile = results.contains { $0.filePath.lowercased().contains("test") }
        #expect(!hasTestFile)
    }

    @Test("Impact analysis returns affected tests and targets")
    func impactAnalysisReturnsAffectedTestsAndTargets() {
        let graph = makeGraph()

        let impact = graph.impact(of: "Sources/Calculator.swift")
        #expect(!impact.affectedTests.isEmpty)
        #expect(!impact.buildTargets.isEmpty)
        #expect(impact.blastRadiusScore > 0)
    }

    // MARK: - Helpers

    private func makeGraph() -> ProgramKnowledgeGraph {
        let symbolNodes = [
            SymbolNode(id: "calc-class", name: "Calculator", kind: .struct, file: "Sources/Calculator.swift", lineStart: 1, lineEnd: 10),
            SymbolNode(id: "helper-fn", name: "helper", kind: .function, file: "Sources/Calculator.swift", lineStart: 12, lineEnd: 15),
            SymbolNode(id: "consumer-class", name: "Consumer", kind: .struct, file: "Sources/Consumer.swift", lineStart: 1, lineEnd: 8),
            SymbolNode(id: "test-calc", name: "testCalculator", kind: .function, file: "Tests/CalculatorTests.swift", lineStart: 1, lineEnd: 5),
        ]

        let symbolGraph = SymbolGraph(
            nodes: symbolNodes,
            edges: [
                SymbolEdge(fromSymbolID: "consumer-class", toSymbolID: "calc-class", kind: .declares),
            ]
        )

        let callGraph = CallGraph(edges: [
            CallEdge(caller: "calc-class", callee: "helper-fn"),
            CallEdge(caller: "consumer-class", callee: "calc-class"),
        ])

        let testGraph = TestGraph(
            tests: [
                RepositoryTest(name: "testCalculator", path: "Tests/CalculatorTests.swift", symbolID: "test-calc"),
            ],
            edges: [
                TestEdge(testSymbolID: "test-calc", targetSymbolID: "calc-class"),
            ]
        )

        let buildGraph = BuildGraph(targets: [
            BuildTarget(
                name: "MainTarget",
                sourceFiles: ["Sources/Calculator.swift", "Sources/Consumer.swift"],
                dependencies: []
            ),
        ])

        let dependencyGraph = DependencyGraph(edges: [
            DependencyEdge(sourcePath: "Sources/Consumer.swift", dependency: "Calculator", toFile: "Sources/Calculator.swift"),
        ])

        let snapshot = RepositorySnapshot(
            id: "test-snapshot",
            workspaceRoot: "/tmp/workspace",
            buildTool: .swiftPackage,
            files: [
                RepositoryFile(path: "Sources/Calculator.swift", isDirectory: false),
                RepositoryFile(path: "Sources/Consumer.swift", isDirectory: false),
                RepositoryFile(path: "Tests/CalculatorTests.swift", isDirectory: false),
            ],
            symbolGraph: symbolGraph,
            dependencyGraph: dependencyGraph,
            callGraph: callGraph,
            testGraph: testGraph,
            buildGraph: buildGraph,
            activeBranch: "main",
            isGitDirty: false
        )

        return ProgramKnowledgeGraph(snapshot: snapshot)
    }
}
