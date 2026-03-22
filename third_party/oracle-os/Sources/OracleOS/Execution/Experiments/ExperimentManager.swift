import Foundation

public final class ExperimentManager: @unchecked Sendable {
    private let runner: ParallelRunner
    private let ranker: PatchRanker
    private let promptEngine: PromptEngine
    private let fileManager = FileManager.default

    public init(
        runner: ParallelRunner = ParallelRunner(),
        ranker: PatchRanker = PatchRanker(),
        promptEngine: PromptEngine = PromptEngine()
    ) {
        self.runner = runner
        self.ranker = ranker
        self.promptEngine = promptEngine
    }

    public func defaultExperimentsRoot(for workspaceRoot: URL) -> URL {
        workspaceRoot.appendingPathComponent(".oracle/experiments", isDirectory: true)
    }

    public func resultsURL(for spec: ExperimentSpec) -> URL {
        let experimentsRoot = defaultExperimentsRoot(
            for: URL(fileURLWithPath: spec.workspaceRoot, isDirectory: true)
        )
        return resultsURL(for: spec, experimentsRoot: experimentsRoot)
    }

    public func run(
        spec: ExperimentSpec,
        architectureRiskScore: Double = 0
    ) async throws -> [ExperimentResult] {
        let bounded = spec.boundedByLimits()
        let workspaceRootURL = URL(fileURLWithPath: bounded.workspaceRoot, isDirectory: true)
        let experimentsRoot = defaultExperimentsRoot(
            for: workspaceRootURL
        )
        try fileManager.createDirectory(at: experimentsRoot, withIntermediateDirectories: true)
        let snapshot = RepositoryIndexer().indexIfNeeded(workspaceRoot: workspaceRootURL)
        let promptDiagnostics = bounded.promptDiagnostics
            ?? promptEngine.experimentGeneration(
                spec: bounded,
                snapshot: snapshot
            ).diagnostics

        let results = try await runner.run(
            spec: bounded,
            experimentsRoot: experimentsRoot,
            architectureRiskScore: architectureRiskScore
        )
        let ranked = ranker.rank(results)
        let selectedID = ranked.first?.candidate.id

        let finalized = ranked.enumerated().map { _, result in
            ExperimentResult(
                id: result.id,
                experimentID: result.experimentID,
                candidate: result.candidate,
                sandboxPath: result.sandboxPath,
                commandResults: result.commandResults,
                diffSummary: result.diffSummary,
                architectureRiskScore: result.architectureRiskScore,
                architectureFindings: result.architectureFindings,
                refactorProposalID: result.refactorProposalID,
                selected: result.candidate.id == selectedID,
                promptDiagnostics: promptDiagnostics
            )
        }
        try persistResults(finalized, spec: spec, experimentsRoot: experimentsRoot)
        return finalized
    }

    public func replaySelected(
        from results: [ExperimentResult]
    ) -> CandidatePatch? {
        results.first(where: \.selected)?.candidate
    }

    public func loadResults(for spec: ExperimentSpec) throws -> [ExperimentResult] {
        let url = resultsURL(for: spec)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([ExperimentResult].self, from: data)
    }

    private func persistResults(
        _ results: [ExperimentResult],
        spec: ExperimentSpec,
        experimentsRoot: URL
    ) throws {
        let resultURL = resultsURL(for: spec, experimentsRoot: experimentsRoot)
        try fileManager.createDirectory(at: resultURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(results)
        try data.write(to: resultURL)
    }

    private func resultsURL(for spec: ExperimentSpec, experimentsRoot: URL) -> URL {
        experimentsRoot
            .appendingPathComponent(spec.id, isDirectory: true)
            .appendingPathComponent("results.json", isDirectory: false)
    }
}
