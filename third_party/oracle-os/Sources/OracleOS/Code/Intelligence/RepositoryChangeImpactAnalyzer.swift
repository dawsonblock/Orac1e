import Foundation

public struct ChangeImpact: Sendable, Equatable {
    public let dependentFiles: [String]
    public let callingFunctions: [String]
    public let affectedTests: [RepositoryTest]
    public let buildTargets: [BuildTarget]
    public let blastRadiusScore: Double

    public init(
        dependentFiles: [String] = [],
        callingFunctions: [String] = [],
        affectedTests: [RepositoryTest] = [],
        buildTargets: [BuildTarget] = [],
        blastRadiusScore: Double = 0
    ) {
        self.dependentFiles = dependentFiles
        self.callingFunctions = callingFunctions
        self.affectedTests = affectedTests
        self.buildTargets = buildTargets
        self.blastRadiusScore = blastRadiusScore
    }
}

public struct RankedCodeCandidate: Sendable, Equatable {
    public let path: String
    public let score: Double
    public let impact: ChangeImpact

    public init(path: String, score: Double, impact: ChangeImpact) {
        self.path = path
        self.score = score
        self.impact = impact
    }
}

public struct RepositoryChangeImpactAnalyzer: Sendable {
    public init() {}

    public func impact(of file: String, in snapshot: RepositorySnapshot) -> ChangeImpact {
        let dependentFiles = snapshot.dependencyGraph.reverseDependencies(of: file)
        let fileSymbols = snapshot.symbolGraph.nodes(inFile: file)
        let fileSymbolIDs = Set(fileSymbols.map(\.id))
        let callingFunctionIDs = fileSymbolIDs.flatMap { snapshot.callGraph.callers(of: $0) }
        let callingFunctions = callingFunctionIDs.compactMap { snapshot.symbolGraph.node(id: $0)?.name }
        let affectedTests = snapshot.testGraph.testsCovering(path: file)
            + fileSymbolIDs.flatMap { snapshot.testGraph.testsCovering(symbolID: $0) }
        let buildTargets = snapshot.buildGraph.targets(containing: file)

        let blastRadiusScore = min(
            1,
            Double(dependentFiles.count) * 0.08
                + Double(callingFunctions.count) * 0.05
                + Double(affectedTests.count) * 0.1
                + Double(buildTargets.count) * 0.08
        )

        return ChangeImpact(
            dependentFiles: dependentFiles.uniqued(),
            callingFunctions: callingFunctions.uniqued(),
            affectedTests: affectedTests.uniqued(by: \.path),
            buildTargets: buildTargets,
            blastRadiusScore: blastRadiusScore
        )
    }

    public func rankCandidates(
        _ files: [String],
        in snapshot: RepositorySnapshot,
        preferredPaths: Set<String> = [],
        avoidedPaths: Set<String> = []
    ) -> [RankedCodeCandidate] {
        files.uniqued().map { path in
            let impact = impact(of: path, in: snapshot)
            var score = 0.4
            score += min(Double(impact.affectedTests.count) * 0.12, 0.24)
            score += min(Double(impact.callingFunctions.count) * 0.05, 0.15)
            if impact.buildTargets.isEmpty == false {
                score += 0.1
            }
            score -= impact.blastRadiusScore * 0.15
            if path.lowercased().contains("test") {
                score -= 0.18
            } else {
                score += 0.05
            }
            if preferredPaths.contains(path) {
                score += 0.2
            }
            if avoidedPaths.contains(path) {
                score -= 0.25
            }
            return RankedCodeCandidate(path: path, score: score, impact: impact)
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.path < rhs.path
            }
            return lhs.score > rhs.score
        }
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}

private extension Array where Element == RepositoryTest {
    func uniqued(by keyPath: KeyPath<RepositoryTest, String>) -> [RepositoryTest] {
        var seen = Set<String>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
