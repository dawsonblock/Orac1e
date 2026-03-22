import Foundation

public struct CodeSearchMatch: Sendable, Equatable {
    public let path: String
    public let score: Double
    public let symbolNames: [String]

    public init(path: String, score: Double, symbolNames: [String]) {
        self.path = path
        self.score = score
        self.symbolNames = symbolNames
    }
}

public struct CodeSearch: Sendable {
    public init() {}

    public func search(
        query: String,
        in snapshot: RepositorySnapshot
    ) -> [CodeSearchMatch] {
        let normalized = query.lowercased()
        let tokens = Set(
            normalized
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "." && $0 != "_" })
                .map(String.init)
                .filter { $0.count > 2 }
        )

        return snapshot.files
            .filter { !$0.isDirectory }
            .map { file in
                let relatedSymbols = snapshot.symbolGraph.nodes(inFile: file.path)
                let symbolHits = relatedSymbols.filter { symbol in
                    tokens.contains(where: { symbol.name.lowercased().contains($0) })
                }
                let pathHit = tokens.contains { file.path.lowercased().contains($0) }
                let dependencyProximity = dependencyScore(for: file.path, snapshot: snapshot, tokens: tokens)
                let testRelationship = snapshot.testGraph.testsCovering(path: file.path).isEmpty ? 0.0 : 0.1
                let recency = recencyScore(file.lastModifiedAt)

                var score = 0.0
                if pathHit { score += 0.35 }
                score += min(Double(symbolHits.count) * 0.15, 0.35)
                score += dependencyProximity
                score += testRelationship
                score += recency

                return CodeSearchMatch(
                    path: file.path,
                    score: score,
                    symbolNames: symbolHits.map(\.name)
                )
            }
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.path < rhs.path
                }
                return lhs.score > rhs.score
            }
    }

    private func dependencyScore(
        for path: String,
        snapshot: RepositorySnapshot,
        tokens: Set<String>
    ) -> Double {
        let directDeps = snapshot.dependencyGraph.directDependencies(of: path)
        let reverseDeps = snapshot.dependencyGraph.reverseDependencies(of: path)
        let depHit = directDeps.contains { dep in
            tokens.contains { dep.lowercased().contains($0) }
        }
        let reverseHit = reverseDeps.contains { dep in
            tokens.contains { dep.lowercased().contains($0) }
        }

        var score = 0.0
        if depHit { score += 0.1 }
        if reverseHit { score += 0.08 }
        return score
    }

    private func recencyScore(_ date: Date?) -> Double {
        guard let date else { return 0 }
        let age = Date().timeIntervalSince(date)
        if age < 60 * 60 * 24 {
            return 0.1
        }
        if age < 60 * 60 * 24 * 7 {
            return 0.05
        }
        return 0
    }
}
