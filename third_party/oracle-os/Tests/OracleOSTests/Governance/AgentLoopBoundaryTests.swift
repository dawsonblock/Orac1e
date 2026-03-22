import Foundation
import Testing
@testable import OracleOS

@Suite("Agent Loop Boundary")
struct AgentLoopBoundaryTests {

    @Test("AgentLoop stays under 150 lines")
    func agentLoopLineCount() throws {
        let content = try agentLoopContents()
        let lineCount = content.split(separator: "\n", omittingEmptySubsequences: false).count
        #expect(lineCount < 150, "AgentLoop.swift should stay under 150 lines, currently \(lineCount)")
    }

    @Test("AgentLoop does not contain plan scoring logic")
    func agentLoopNoPlanScoring() throws {
        let content = try agentLoopContents()
        #expect(!content.contains("PlanCandidate"), "AgentLoop should not reference PlanCandidate")
        #expect(!content.contains("planEvaluator"), "AgentLoop should not reference planEvaluator")
        #expect(!content.contains("PlanScore"), "AgentLoop should not reference PlanScore")
    }

    @Test("AgentLoop does not contain memory routing")
    func agentLoopNoMemoryRouting() throws {
        let content = try agentLoopContents()
        #expect(!content.contains("MemoryRouter("), "AgentLoop should not instantiate MemoryRouter")
        #expect(!content.contains("PatternMemoryStore("), "AgentLoop should not instantiate PatternMemoryStore")
        #expect(!content.contains("ExecutionMemoryStore("), "AgentLoop should not instantiate ExecutionMemoryStore")
    }

    @Test("AgentLoop does not contain graph updates")
    func agentLoopNoGraphUpdates() throws {
        let content = try agentLoopContents()
        #expect(!content.contains("graphStore.recordTransition"), "AgentLoop should not record graph transitions directly")
        #expect(!content.contains("graphStore.promote"), "AgentLoop should not promote graph edges directly")
        #expect(!content.contains("graphStore.insert"), "AgentLoop should not insert into graph directly")
    }

    @Test("AgentLoop does not contain architecture analysis")
    func agentLoopNoArchitectureAnalysis() throws {
        let content = try agentLoopContents()
        #expect(!content.contains("ArchitectureEngine("), "AgentLoop should not instantiate ArchitectureEngine")
        #expect(!content.contains("architectureEngine.review"), "AgentLoop should not call architectureEngine.review")
    }

    @Test("AgentLoop does not contain experiment comparison")
    func agentLoopNoExperimentComparison() throws {
        let content = try agentLoopContents()
        #expect(!content.contains("ResultComparator("), "AgentLoop should not instantiate ResultComparator")
        #expect(!content.contains("PatchRanker("), "AgentLoop should not instantiate PatchRanker")
        #expect(!content.contains("comparator.sort"), "AgentLoop should not sort comparator results")
    }

    private func agentLoopContents() throws -> String {
        let agentLoopURL = repositoryRoot().appendingPathComponent(
            "Sources/OracleOS/Execution/Loop/AgentLoop.swift",
            isDirectory: false
        )
        return try String(contentsOf: agentLoopURL)
    }

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default

        while true {
            let packageManifestURL = url.appendingPathComponent("Package.swift")
            if fileManager.fileExists(atPath: packageManifestURL.path) {
                return url
            }

            let parent = url.deletingLastPathComponent()
            if parent.path == url.path {
                return url
            }

            url = parent
        }
    }
}
