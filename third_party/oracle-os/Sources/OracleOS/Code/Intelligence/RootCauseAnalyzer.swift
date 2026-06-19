import Foundation

public struct RootCauseCandidate: Sendable, Equatable {
    public let path: String
    public let score: Double
    public let matchedSymbols: [String]
    public let matchedTests: [String]
    public let reasons: [String]
    public let impact: ChangeImpact

    public init(
        path: String,
        score: Double,
        matchedSymbols: [String] = [],
        matchedTests: [String] = [],
        reasons: [String] = [],
        impact: ChangeImpact = ChangeImpact()
    ) {
        self.path = path
        self.score = score
        self.matchedSymbols = matchedSymbols
        self.matchedTests = matchedTests
        self.reasons = reasons
        self.impact = impact
    }
}

public struct RootCauseAnalyzer: Sendable {
    private let search: CodeSearch
    private let impactAnalyzer: RepositoryChangeImpactAnalyzer

    public init(
        search: CodeSearch = CodeSearch(),
        impactAnalyzer: RepositoryChangeImpactAnalyzer = RepositoryChangeImpactAnalyzer()
    ) {
        self.search = search
        self.impactAnalyzer = impactAnalyzer
    }

    public func analyze(
        failingTest testSymbolID: String,
        in snapshot: RepositorySnapshot,
        preferredPaths: Set<String> = [],
        avoidedPaths: Set<String> = []
    ) -> [RootCauseCandidate] {
        let targetSymbolIDs = snapshot.testGraph.targetSymbolIDs(for: testSymbolID)
        let targetSymbols = targetSymbolIDs.compactMap { snapshot.symbolGraph.node(id: $0) }
        let targetFiles = targetSymbols.map(\.file)
        let callers = targetSymbolIDs.flatMap { snapshot.callGraph.callers(of: $0) }
            .compactMap { snapshot.symbolGraph.node(id: $0) }
        let reverseDependencies = targetFiles.flatMap { snapshot.dependencyGraph.reverseDependencies(of: $0) }

        return rankCandidates(
            signalPaths: targetFiles + callers.map(\.file) + reverseDependencies,
            matchedSymbols: Dictionary(
                grouping: targetSymbols + callers,
                by: \.file
            ).mapValues { $0.map(\.name).uniqued() },
            matchedTests: matchedTestsByTargetPath(for: [testSymbolID], in: snapshot),
            preferredPaths: preferredPaths,
            avoidedPaths: avoidedPaths,
            in: snapshot,
            baseReasons: Dictionary(
                uniqueKeysWithValues: targetFiles.map { ($0, ["test graph mapped failing test to target file"]) }
            )
        )
    }

    public func analyze(
        failureDescription: String,
        in snapshot: RepositorySnapshot,
        preferredPaths: Set<String> = [],
        avoidedPaths: Set<String> = []
    ) -> [RootCauseCandidate] {
        let explicitPaths = extractExplicitPaths(from: failureDescription, snapshot: snapshot)
        let matchedTests = matchingTests(in: failureDescription, snapshot: snapshot)
        let matchedTestIDs = matchedTests.compactMap(\.symbolID)
        let testTargetSymbolIDs = matchedTestIDs.flatMap { snapshot.testGraph.targetSymbolIDs(for: $0) }
        let testDrivenFiles = testTargetSymbolIDs.compactMap { snapshot.symbolGraph.node(id: $0)?.file }
        let directSymbols = matchedSymbols(in: failureDescription, snapshot: snapshot)
        let callerSymbols = directSymbols.flatMap { symbol in
            snapshot.callGraph.callers(of: symbol.id)
                .compactMap { snapshot.symbolGraph.node(id: $0) }
        }
        let calleeSymbols = directSymbols.flatMap { symbol in
            snapshot.callGraph.callees(of: symbol.id)
                .compactMap { snapshot.symbolGraph.node(id: $0) }
        }
        let dependencyPaths = (directSymbols + callerSymbols + calleeSymbols).flatMap { symbol in
            snapshot.dependencyGraph.reverseDependencies(of: symbol.file)
                + snapshot.dependencyGraph.directDependencies(of: symbol.file)
        }
        let searchMatches = search.search(query: failureDescription, in: snapshot)

        let signalPaths = explicitPaths
            + matchedTests.map(\.path)
            + testDrivenFiles
            + directSymbols.map(\.file)
            + callerSymbols.map(\.file)
            + calleeSymbols.map(\.file)
            + dependencyPaths
            + searchMatches.map(\.path)

        let symbolMatchesByPath = Dictionary(
            grouping: directSymbols + callerSymbols + calleeSymbols,
            by: \.file
        ).mapValues { $0.map(\.name).uniqued() }

        var reasonsByPath: [String: [String]] = [:]
        for path in explicitPaths {
            reasonsByPath[path, default: []].append("failure description named file explicitly")
        }
        for test in matchedTests {
            reasonsByPath[test.path, default: []].append("failure description matched test \(test.name)")
        }
        for path in testDrivenFiles {
            reasonsByPath[path, default: []].append("test graph mapped matched test to target file")
        }
        for symbol in directSymbols {
            reasonsByPath[symbol.file, default: []].append("failure description matched symbol \(symbol.name)")
        }
        for symbol in callerSymbols {
            reasonsByPath[symbol.file, default: []].append("call graph traced caller of matched symbol")
        }
        for symbol in calleeSymbols {
            reasonsByPath[symbol.file, default: []].append("call graph traced callee of matched symbol")
        }
        for path in dependencyPaths {
            reasonsByPath[path, default: []].append("dependency graph is close to a matched symbol")
        }
        for match in searchMatches where match.score > 0 {
            reasonsByPath[match.path, default: []].append("code search score \(String(format: "%.2f", match.score))")
        }

        let matchedTestsByPath = matchedTestsByTargetPath(for: matchedTestIDs, in: snapshot)
        var ranked = rankCandidates(
            signalPaths: signalPaths,
            matchedSymbols: symbolMatchesByPath,
            matchedTests: matchedTestsByPath,
            preferredPaths: preferredPaths,
            avoidedPaths: avoidedPaths,
            in: snapshot,
            baseReasons: reasonsByPath,
            searchScores: Dictionary(uniqueKeysWithValues: searchMatches.map { ($0.path, $0.score) }),
            explicitPaths: Set(explicitPaths)
        )

        if ranked.isEmpty, failureDescription.lowercased().contains("test") {
            let fallbackPaths = snapshot.testGraph.tests.prefix(5).map(\.path)
            ranked = rankCandidates(
                signalPaths: Array(fallbackPaths),
                matchedSymbols: [:],
                matchedTests: Dictionary(uniqueKeysWithValues: fallbackPaths.map { ($0, [URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent]) }),
                preferredPaths: preferredPaths,
                avoidedPaths: avoidedPaths,
                in: snapshot,
                baseReasons: Dictionary(uniqueKeysWithValues: fallbackPaths.map { ($0, ["fallback to nearby tests"]) })
            )
        }

        return ranked
    }

    private func rankCandidates(
        signalPaths: [String],
        matchedSymbols: [String: [String]],
        matchedTests: [String: [String]],
        preferredPaths: Set<String>,
        avoidedPaths: Set<String>,
        in snapshot: RepositorySnapshot,
        baseReasons: [String: [String]],
        searchScores: [String: Double] = [:],
        explicitPaths: Set<String> = []
    ) -> [RootCauseCandidate] {
        let counts = signalPaths.reduce(into: [String: Int]()) { partialResult, path in
            partialResult[path, default: 0] += 1
        }

        let recentEditPaths = Self.recentlyEditedPaths(in: snapshot)

        return signalPaths.uniquedPreservingOrder().map { path in
            let impact = impactAnalyzer.impact(of: path, in: snapshot)
            let signalScore = min(Double(counts[path, default: 0]) * 0.18, 0.45)
            let searchScore = min(searchScores[path, default: 0] * 0.35, 0.2)
            let explicitBonus = explicitPaths.contains(path) ? 0.25 : 0
            let symbolBonus = min(Double(matchedSymbols[path, default: []].count) * 0.08, 0.16)
            let testBonus = min(Double(matchedTests[path, default: []].count) * 0.12, 0.24)
            let preferredBonus = preferredPaths.contains(path) ? 0.22 : 0
            let recentEditBonus = recentEditPaths.contains(path) ? 0.12 : 0
            let avoidedPenalty = avoidedPaths.contains(path) ? 0.3 : 0
            let testFilePenalty = path.lowercased().contains("test") ? 0.15 : 0
            let blastRadiusPenalty = impact.blastRadiusScore * 0.12

            let score = 0.35
                + signalScore
                + searchScore
                + explicitBonus
                + symbolBonus
                + testBonus
                + preferredBonus
                + recentEditBonus
                - avoidedPenalty
                - testFilePenalty
                - blastRadiusPenalty

            var reasons = baseReasons[path, default: []]
            if preferredPaths.contains(path) {
                reasons.append("memory or project context prefers this path")
            }
            if avoidedPaths.contains(path) {
                reasons.append("memory or project context marks this path as risky")
            }
            if recentEditPaths.contains(path) {
                reasons.append("recently edited file is more likely root cause")
            }
            if impact.blastRadiusScore > 0.3 {
                reasons.append("blast radius \(String(format: "%.2f", impact.blastRadiusScore)) reduces confidence")
            }

            return RootCauseCandidate(
                path: path,
                score: score,
                matchedSymbols: matchedSymbols[path, default: []].sorted(),
                matchedTests: matchedTests[path, default: []].sorted(),
                reasons: reasons.uniquedPreservingOrder(),
                impact: impact
            )
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.path < rhs.path
            }
            return lhs.score > rhs.score
        }
    }

    private static func recentlyEditedPaths(in snapshot: RepositorySnapshot) -> Set<String> {
        let recentThreshold: TimeInterval = 3600
        let now = Date()
        return Set(
            snapshot.files
                .filter { file in
                    guard let modified = file.lastModifiedAt else { return false }
                    return now.timeIntervalSince(modified) < recentThreshold
                }
                .map(\.path)
        )
    }

    private func extractExplicitPaths(
        from text: String,
        snapshot: RepositorySnapshot
    ) -> [String] {
        let regex = try? NSRegularExpression(pattern: #"[A-Za-z0-9_./-]+\.(swift|ts|tsx|js|jsx|py)"#)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex?.matches(in: text, range: range) ?? []
        let paths = matches.compactMap { match -> String? in
            guard let pathRange = Range(match.range, in: text) else { return nil }
            return String(text[pathRange])
        }
        return paths.filter { candidate in
            snapshot.files.contains { $0.path == candidate }
        }.uniquedPreservingOrder()
    }

    private func matchingTests(
        in text: String,
        snapshot: RepositorySnapshot
    ) -> [RepositoryTest] {
        let lowered = text.lowercased()
        return snapshot.testGraph.tests.filter { test in
            lowered.contains(test.name.lowercased())
                || lowered.contains(URL(fileURLWithPath: test.path).deletingPathExtension().lastPathComponent.lowercased())
        }
    }

    private func matchedSymbols(
        in text: String,
        snapshot: RepositorySnapshot
    ) -> [SymbolNode] {
        let tokens = Set(
            text.lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })
                .map(String.init)
                .filter { $0.count > 2 }
        )

        return snapshot.symbolGraph.nodes.filter { node in
            let lowered = node.name.lowercased()
            return tokens.contains { token in
                lowered.contains(token) || token.contains(lowered)
            }
        }
    }

    private func matchedTestsByTargetPath(
        for testIDs: [String],
        in snapshot: RepositorySnapshot
    ) -> [String: [String]] {
        let tests = snapshot.testGraph.tests.filter { test in
            guard let symbolID = test.symbolID else { return false }
            return testIDs.contains(symbolID)
        }
        let namesByID: [String: String] = Dictionary(
            uniqueKeysWithValues: tests.compactMap { test in
                guard let symbolID = test.symbolID else { return nil }
                return (symbolID, test.name)
            }
        )

        var grouped: [String: [String]] = [:]
        for testID in testIDs {
            let targetPaths = snapshot.testGraph.targetSymbolIDs(for: testID)
                .compactMap { snapshot.symbolGraph.node(id: $0)?.file }
                .uniquedPreservingOrder()
            for path in targetPaths {
                if let testName = namesByID[testID] {
                    grouped[path, default: []].append(testName)
                }
            }
        }

        return grouped.mapValues { $0.uniqued() }
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }

    func uniquedPreservingOrder() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
