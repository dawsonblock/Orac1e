import Foundation
import Testing
@testable import OracleOS

@Suite("Root Cause Ranking")
struct RootCauseRankingTests {

    @Test("Root cause analyzer produces ranked candidates")
    func analyzerProducesRankedCandidates() {
        let analyzer = RootCauseAnalyzer()
        let snapshot = makeMinimalSnapshot()

        let candidates = analyzer.analyze(
            failureDescription: "Calculator.swift add method returns wrong result",
            in: snapshot
        )

        // Should return candidates sorted by score
        for i in 0..<max(candidates.count - 1, 0) {
            #expect(candidates[i].score >= candidates[i + 1].score)
        }
    }

    @Test("Root cause candidates include reasons")
    func candidatesIncludeReasons() {
        let candidate = RootCauseCandidate(
            path: "Sources/Calculator.swift",
            score: 0.85,
            matchedSymbols: ["add"],
            matchedTests: ["testAdd"],
            reasons: ["failure description matched symbol add"]
        )

        #expect(!candidate.reasons.isEmpty)
        #expect(candidate.score > 0)
        #expect(!candidate.matchedSymbols.isEmpty)
    }

    @Test("Preferred paths boost root cause ranking")
    func preferredPathsBoostRanking() {
        let analyzer = RootCauseAnalyzer()
        let snapshot = makeMinimalSnapshot()

        let preferredPath = "Sources/Calculator.swift"

        let withPreferred = analyzer.analyze(
            failureDescription: "Calculator error",
            in: snapshot,
            preferredPaths: Set([preferredPath])
        )
        let withoutPreferred = analyzer.analyze(
            failureDescription: "Calculator error",
            in: snapshot,
            preferredPaths: Set()
        )

        // Both should produce non-empty results without crashing
        #expect(!withPreferred.isEmpty)
        #expect(!withoutPreferred.isEmpty)

        // Preferred path should be boosted to the top of the ranking
        #expect(withPreferred.first?.path == preferredPath)

        // The preferred path should still be present without preferences
        #expect(withoutPreferred.map(\.path).contains(preferredPath))
    }

    private func makeMinimalSnapshot() -> RepositorySnapshot {
        RepositorySnapshot(
            id: "test-repo",
            workspaceRoot: "/tmp/workspace",
            buildTool: .swiftPackage,
            files: [
                RepositoryFile(path: "Sources/Calculator.swift", isDirectory: false),
                RepositoryFile(path: "Tests/CalculatorTests.swift", isDirectory: false),
            ],
            symbolGraph: SymbolGraph(),
            dependencyGraph: DependencyGraph(),
            testGraph: TestGraph(),
            activeBranch: "main",
            isGitDirty: false
        )
    }
}
