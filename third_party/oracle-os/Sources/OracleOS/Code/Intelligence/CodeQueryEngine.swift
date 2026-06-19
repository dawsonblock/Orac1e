import Foundation

public struct CodeQueryEngine: Sendable {
    private let impactAnalyzer: RepositoryChangeImpactAnalyzer
    private let rootCauseAnalyzer: RootCauseAnalyzer

    public init(
        search: CodeSearch = CodeSearch(),
        impactAnalyzer: RepositoryChangeImpactAnalyzer = RepositoryChangeImpactAnalyzer(),
        rootCauseAnalyzer: RootCauseAnalyzer? = nil
    ) {
        self.impactAnalyzer = impactAnalyzer
        self.rootCauseAnalyzer = rootCauseAnalyzer ?? RootCauseAnalyzer(
            search: search,
            impactAnalyzer: impactAnalyzer
        )
    }

    public func findSymbol(
        named name: String,
        in snapshot: RepositorySnapshot
    ) -> [SymbolNode] {
        snapshot.symbolGraph.nodes(named: name)
    }

    public func findCallers(
        of symbolID: String,
        in snapshot: RepositorySnapshot
    ) -> [SymbolNode] {
        let callerIDs = Set(snapshot.callGraph.callers(of: symbolID))
        return snapshot.symbolGraph.nodes.filter { callerIDs.contains($0.id) }
    }

    public func findDependencies(
        of file: String,
        in snapshot: RepositorySnapshot
    ) -> [String] {
        snapshot.dependencyGraph.directDependencies(of: file)
    }

    public func findTests(
        covering symbolID: String,
        in snapshot: RepositorySnapshot
    ) -> [RepositoryTest] {
        snapshot.testGraph.testsCovering(symbolID: symbolID)
    }

    public func findFilesReferencing(
        symbol name: String,
        in snapshot: RepositorySnapshot
    ) -> [String] {
        let normalized = name.lowercased()
        let referencedSymbols = snapshot.symbolGraph.nodes.filter { $0.name.lowercased() == normalized }
        let referenceFiles = referencedSymbols.flatMap { symbol in
            snapshot.callGraph.callers(of: symbol.id)
                .compactMap { snapshot.symbolGraph.node(id: $0)?.file }
        }
        let dependencyFiles = snapshot.dependencyGraph.edges
            .filter { $0.dependency.lowercased().contains(normalized) || ($0.toFile?.lowercased().contains(normalized) ?? false) }
            .map(\.sourcePath)
        return (referenceFiles + dependencyFiles).uniqued()
    }

    public func findLikelyRootCause(
        failingTest testSymbolID: String,
        in snapshot: RepositorySnapshot
    ) -> [RankedCodeCandidate] {
        findLikelyRootCause(
            failingTest: testSymbolID,
            in: snapshot,
            preferredPaths: [],
            avoidedPaths: []
        )
    }

    public func findLikelyRootCause(
        failingTest testSymbolID: String,
        in snapshot: RepositorySnapshot,
        preferredPaths: Set<String>,
        avoidedPaths: Set<String>
    ) -> [RankedCodeCandidate] {
        rootCauseAnalyzer.analyze(
            failingTest: testSymbolID,
            in: snapshot,
            preferredPaths: preferredPaths,
            avoidedPaths: avoidedPaths
        )
        .map { RankedCodeCandidate(path: $0.path, score: $0.score, impact: $0.impact) }
    }

    public func findLikelyRootCause(
        failureDescription: String,
        in snapshot: RepositorySnapshot
    ) -> [RankedCodeCandidate] {
        findLikelyRootCause(
            failureDescription: failureDescription,
            in: snapshot,
            preferredPaths: [],
            avoidedPaths: []
        )
    }

    public func findLikelyRootCause(
        failureDescription: String,
        in snapshot: RepositorySnapshot,
        preferredPaths: Set<String>,
        avoidedPaths: Set<String>
    ) -> [RankedCodeCandidate] {
        rootCauseAnalyzer.analyze(
            failureDescription: failureDescription,
            in: snapshot,
            preferredPaths: preferredPaths,
            avoidedPaths: avoidedPaths
        )
        .map { RankedCodeCandidate(path: $0.path, score: $0.score, impact: $0.impact) }
    }

    public func impact(
        of file: String,
        in snapshot: RepositorySnapshot
    ) -> ChangeImpact {
        impactAnalyzer.impact(of: file, in: snapshot)
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
