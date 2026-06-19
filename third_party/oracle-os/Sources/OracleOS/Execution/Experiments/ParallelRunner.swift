import Foundation

public final class ParallelRunner: @unchecked Sendable {
    private let workspaceRunner: WorkspaceRunner
    private let repositoryIndexer: RepositoryIndexer
    private let architectureEngine: ArchitectureEngine

    public init(
        workspaceRunner: WorkspaceRunner = WorkspaceRunner(),
        repositoryIndexer: RepositoryIndexer = RepositoryIndexer(),
        architectureEngine: ArchitectureEngine = ArchitectureEngine()
    ) {
        self.workspaceRunner = workspaceRunner
        self.repositoryIndexer = repositoryIndexer
        self.architectureEngine = architectureEngine
    }

    public func run(
        spec: ExperimentSpec,
        experimentsRoot: URL,
        architectureRiskScore: Double
    ) async throws -> [ExperimentResult] {
        let workspaceRoot = URL(fileURLWithPath: spec.workspaceRoot, isDirectory: true)
        let workspaceRunner = self.workspaceRunner
        let repositoryIndexer = self.repositoryIndexer
        let architectureEngine = self.architectureEngine

        return try await withThrowingTaskGroup(of: ExperimentResult.self) { group in
            for candidate in spec.candidates {
                group.addTask {
                    let sandbox = try WorktreeSandbox.create(
                        experimentID: spec.id,
                        candidateID: candidate.id,
                        workspaceRoot: workspaceRoot,
                        experimentsRoot: experimentsRoot
                    )
                    let buildTool = BuildToolDetector.detect(at: URL(fileURLWithPath: sandbox.sandboxPath, isDirectory: true))
                    let buildCommand = spec.buildCommand.map {
                        CommandSpec(
                            category: $0.category,
                            executable: $0.executable,
                            arguments: $0.arguments,
                            workspaceRoot: sandbox.sandboxPath,
                            workspaceRelativePath: $0.workspaceRelativePath,
                            summary: $0.summary,
                            mutatesWorkspace: $0.mutatesWorkspace,
                            touchesNetwork: $0.touchesNetwork
                        )
                    } ?? BuildToolDetector.defaultBuildCommand(
                        for: buildTool,
                        workspaceRoot: URL(fileURLWithPath: sandbox.sandboxPath, isDirectory: true)
                    )
                    let testCommand = spec.testCommand.map {
                        CommandSpec(
                            category: $0.category,
                            executable: $0.executable,
                            arguments: $0.arguments,
                            workspaceRoot: sandbox.sandboxPath,
                            workspaceRelativePath: $0.workspaceRelativePath,
                            summary: $0.summary,
                            mutatesWorkspace: $0.mutatesWorkspace,
                            touchesNetwork: $0.touchesNetwork
                        )
                    } ?? BuildToolDetector.defaultTestCommand(
                        for: buildTool,
                        workspaceRoot: URL(fileURLWithPath: sandbox.sandboxPath, isDirectory: true)
                    )

                    let executedCommands = [buildCommand, testCommand]
                        .compactMap { $0 }
                        .map {
                            ExperimentExecutedCommand(
                                category: $0.category.rawValue,
                                executable: $0.executable,
                                arguments: $0.arguments,
                                workspaceRoot: $0.workspaceRoot,
                                summary: $0.summary
                            )
                        }

                    do {
                        try sandbox.apply(candidate)

                        var results: [CommandResult] = []
                        if let buildCommand {
                            results.append(try workspaceRunner.execute(spec: buildCommand))
                        }
                        if results.allSatisfy(\.succeeded), let testCommand {
                            results.append(try workspaceRunner.execute(spec: testCommand))
                        }

                        let diffSummary = sandbox.diffSummary()
                        let candidateSnapshot = repositoryIndexer.indexIfNeeded(
                            workspaceRoot: URL(fileURLWithPath: sandbox.sandboxPath, isDirectory: true)
                        )
                        let architectureReview = architectureEngine.reviewCandidatePatch(
                            goalDescription: spec.goalDescription,
                            snapshot: candidateSnapshot,
                            candidate: candidate,
                            diffSummary: diffSummary
                        )
                        let effectiveArchitectureRisk = max(architectureRiskScore, architectureReview.riskScore)
                        let cleanupOutcome = sandbox.cleanup()

                        return ExperimentResult(
                            experimentID: spec.id,
                            candidate: candidate,
                            sandboxPath: sandbox.sandboxPath,
                            commandResults: results,
                            diffSummary: diffSummary,
                            architectureRiskScore: effectiveArchitectureRisk,
                            architectureFindings: architectureReview.findings,
                            refactorProposalID: architectureReview.refactorProposal?.id,
                            isolationMetadata: ExperimentIsolationMetadata(
                                canonicalWorkspaceRoot: sandbox.canonicalWorkspaceRoot,
                                sandboxRoot: sandbox.experimentsRoot,
                                resolvedSandboxRoot: sandbox.canonicalSandboxPath,
                                candidatePaths: [candidate.workspaceRelativePath],
                                executedCommands: executedCommands,
                                cleanupOutcome: cleanupOutcome
                            )
                        )
                    } catch {
                        _ = sandbox.cleanup()
                        throw error
                    }
                }
            }

            var collected: [ExperimentResult] = []
            for try await result in group {
                collected.append(result)
            }
            return collected
        }
    }
}
