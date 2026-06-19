import Foundation

/// A unified query interface over all code-intelligence graphs.
///
/// ``ProgramKnowledgeGraph`` integrates the five structural graphs produced
/// by ``RepositoryIndexer`` into a single substrate the planner can reason
/// about:
///
/// | Graph             | Purpose                                  |
/// |-------------------|------------------------------------------|
/// | ``SymbolGraph``   | Symbols, their kinds, and relationships  |
/// | ``CallGraph``     | Caller → callee edges                    |
/// | ``TestGraph``     | Test ↔ subject coverage                  |
/// | ``BuildGraph``    | Build targets and source ownership       |
/// | ``DependencyGraph``| File-level import / dependency edges    |
///
/// Higher-level queries such as "trace a test failure to its root cause"
/// compose primitives from multiple graphs, giving the planner
/// program-structure-aware reasoning without exposing raw graph details.
///
/// ``ProgramKnowledgeGraph`` is the **canonical code model**.  All structural
/// code-intelligence graphs (``SymbolGraph``, ``CallGraph``, ``TestGraph``,
/// ``BuildGraph``, ``DependencyGraph``) are **views** over this single model.
///
/// Consumers should query code structure through this type rather than
/// accessing individual graphs directly.  This ensures stable identity for
/// files, modules, classes, functions, and tests across the codebase.
///
/// Pipeline position:
///
///     filesystem observation
///     ↓
///     RepositoryIndexer
///     ↓
///     ProgramKnowledgeGraph   ← this type
///     ↓
///     planner
///
public struct ProgramKnowledgeGraph: Sendable {

    public let snapshot: RepositorySnapshot

    public init(snapshot: RepositorySnapshot) {
        self.snapshot = snapshot
    }

    // MARK: - Convenience accessors

    public var symbolGraph: SymbolGraph { snapshot.symbolGraph }
    public var callGraph: CallGraph { snapshot.callGraph }
    public var testGraph: TestGraph { snapshot.testGraph }
    public var buildGraph: BuildGraph { snapshot.buildGraph }
    public var dependencyGraph: DependencyGraph { snapshot.dependencyGraph }

    // MARK: - Symbol queries

    /// Find all symbols matching a name (case-insensitive substring match).
    public func symbols(named name: String) -> [SymbolNode] {
        symbolGraph.nodes(named: name)
    }

    /// Find all symbols defined in a specific file.
    public func symbols(inFile path: String) -> [SymbolNode] {
        symbolGraph.nodes(inFile: path)
    }

    /// Find a symbol by its unique ID.
    public func symbol(id: String) -> SymbolNode? {
        symbolGraph.node(id: id)
    }

    // MARK: - Call-graph queries

    /// Return the direct callers of a symbol.
    public func callers(of symbolID: String) -> [SymbolNode] {
        let callerIDs = Set(callGraph.callers(of: symbolID))
        return symbolGraph.nodes.filter { callerIDs.contains($0.id) }
    }

    /// Return the direct callees of a symbol.
    public func callees(of symbolID: String) -> [SymbolNode] {
        let calleeIDs = Set(callGraph.callees(of: symbolID))
        return symbolGraph.nodes.filter { calleeIDs.contains($0.id) }
    }

    /// Expand the call graph outward from a starting symbol up to `depth`
    /// hops, returning all reachable symbol IDs (callers + callees).
    public func callNeighborhood(
        of symbolID: String,
        depth: Int = 2
    ) -> Set<String> {
        var visited = Set<String>()
        var frontier: Set<String> = [symbolID]

        for _ in 0..<depth {
            let next = frontier.flatMap { id in
                callGraph.callers(of: id) + callGraph.callees(of: id)
            }
            frontier = Set(next).subtracting(visited)
            visited.formUnion(frontier)
        }

        return visited
    }

    // MARK: - Test coverage queries

    /// Return tests that cover a given symbol.
    public func tests(covering symbolID: String) -> [RepositoryTest] {
        testGraph.testsCovering(symbolID: symbolID)
    }

    /// Return tests whose file path covers a given source path.
    public func tests(coveringFile path: String) -> [RepositoryTest] {
        testGraph.testsCovering(path: path)
    }

    /// Return the source symbol IDs that a test exercises.
    public func targets(of testSymbolID: String) -> [SymbolNode] {
        let targetIDs = testGraph.targetSymbolIDs(for: testSymbolID)
        return targetIDs.compactMap { symbolGraph.node(id: $0) }
    }

    // MARK: - Dependency queries

    /// Direct import-level dependencies of a file.
    public func dependencies(of path: String) -> [String] {
        dependencyGraph.directDependencies(of: path)
    }

    /// Files that depend on the given path (reverse dependencies).
    public func dependents(of path: String) -> [String] {
        dependencyGraph.reverseDependencies(of: path)
    }

    // MARK: - Build queries

    /// Build targets that include a given source file.
    public func buildTargets(containing file: String) -> [BuildTarget] {
        buildGraph.targets(containing: file)
    }

    // MARK: - Composite queries

    /// Trace a failing test back through the call graph to find the most
    /// likely root-cause source files, ranked by structural relevance.
    ///
    /// Pipeline:
    ///
    ///     test failure
    ///     ↓ identify failing symbol
    ///     ↓ trace call graph
    ///     ↓ locate root cause candidates
    ///     ↓ rank by coverage + blast radius
    ///
    public func traceFailure(
        testSymbolID: String
    ) -> [ProgramTraceResult] {
        // 1. Find which source symbols the test covers.
        let targetIDs = testGraph.targetSymbolIDs(for: testSymbolID)
        guard !targetIDs.isEmpty else { return [] }

        // 2. Expand each target through the call graph.
        var candidateFiles: [String: Double] = [:]
        for targetID in targetIDs {
            let neighborhood = callNeighborhood(of: targetID, depth: 2)
            let allIDs = neighborhood.union([targetID])
            for id in allIDs {
                guard let node = symbolGraph.node(id: id) else { continue }
                // Direct targets get the highest score; neighbors are discounted
                // by graph distance.
                let weight: Double = (id == targetID) ? 1.0 : 0.5
                candidateFiles[node.file, default: 0] += weight
            }
        }

        // 3. Build results sorted by aggregate score.
        return candidateFiles
            .map { file, score in
                let fileSymbols = symbolGraph.nodes(inFile: file)
                let coveredTests = testGraph.testsCovering(path: file)
                let targets = buildGraph.targets(containing: file)
                return ProgramTraceResult(
                    filePath: file,
                    score: score,
                    matchedSymbols: fileSymbols.map(\.name),
                    coveredTests: coveredTests,
                    buildTargets: targets
                )
            }
            .filter { !$0.filePath.lowercased().contains("test") }
            .sorted { $0.score > $1.score }
    }

    /// Compute the full impact of changing a file: dependent files, calling
    /// functions, affected tests, and build targets.
    public func impact(of file: String) -> ChangeImpact {
        RepositoryChangeImpactAnalyzer().impact(of: file, in: snapshot)
    }
}

/// The result of tracing a test failure through the program knowledge graph.
public struct ProgramTraceResult: Sendable {
    public let filePath: String
    public let score: Double
    public let matchedSymbols: [String]
    public let coveredTests: [RepositoryTest]
    public let buildTargets: [BuildTarget]

    public init(
        filePath: String,
        score: Double,
        matchedSymbols: [String] = [],
        coveredTests: [RepositoryTest] = [],
        buildTargets: [BuildTarget] = []
    ) {
        self.filePath = filePath
        self.score = score
        self.matchedSymbols = matchedSymbols
        self.coveredTests = coveredTests
        self.buildTargets = buildTargets
    }
}
