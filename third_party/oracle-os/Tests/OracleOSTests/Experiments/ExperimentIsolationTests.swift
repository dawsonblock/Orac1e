import Foundation
import Testing
@testable import OracleOS

@Suite("Experiment Isolation")
struct ExperimentIsolationTests {

    @Test("Sandbox rejects traversal and symlink escape attempts")
    func sandboxRejectsEscapes() throws {
        let root = makeTempDirectory()
        let workspaceRoot = root.appendingPathComponent("workspace", isDirectory: true)
        let experimentsRoot = workspaceRoot.appendingPathComponent(".oracle/experiments", isDirectory: true)
        let sandboxRoot = experimentsRoot.appendingPathComponent("exp-1/candidate-a", isDirectory: true)
        let outsideRoot = root.appendingPathComponent("outside", isDirectory: true)

        try FileManager.default.createDirectory(at: sandboxRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sandboxRoot.appendingPathComponent("linked", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: sandboxRoot.appendingPathComponent("linked", isDirectory: true))
        try FileManager.default.createSymbolicLink(
            at: sandboxRoot.appendingPathComponent("linked", isDirectory: true),
            withDestinationURL: outsideRoot
        )

        let sandbox = WorktreeSandbox(
            experimentID: "exp-1",
            candidateID: "candidate-a",
            workspaceRoot: workspaceRoot.path,
            experimentsRoot: experimentsRoot.path,
            sandboxPath: sandboxRoot.path,
            canonicalWorkspaceRoot: workspaceRoot.standardizedFileURL.path,
            canonicalSandboxPath: sandboxRoot.standardizedFileURL.path,
            branchName: "test"
        )

        #expect(throws: Error.self) {
            try sandbox.apply(
                CandidatePatch(
                    id: "escape-traversal",
                    title: "Traversal",
                    summary: "Escape sandbox with ..",
                    workspaceRelativePath: "../outside.txt",
                    content: "blocked"
                )
            )
        }

        #expect(throws: Error.self) {
            try sandbox.apply(
                CandidatePatch(
                    id: "escape-symlink",
                    title: "Symlink",
                    summary: "Escape sandbox through symlink",
                    workspaceRelativePath: "linked/outside.txt",
                    content: "blocked"
                )
            )
        }
    }

    @Test("Parallel runner records sandbox isolation metadata")
    func parallelRunnerRecordsIsolationMetadata() async throws {
        let workspaceRoot = makeGitWorkspace()
        let experimentsRoot = workspaceRoot.appendingPathComponent(".oracle/experiments", isDirectory: true)
        let spec = ExperimentSpec(
            goalDescription: "Apply bounded patch candidate",
            workspaceRoot: workspaceRoot.path,
            candidates: [
                CandidatePatch(
                    id: "candidate-1",
                    title: "Patch file",
                    summary: "Adjust sample source",
                    workspaceRelativePath: "Sources/Sample.swift",
                    content: "enum Sample { static let value = 2 }\n"
                ),
            ],
            buildCommand: CommandSpec(
                category: .build,
                executable: "/usr/bin/env",
                arguments: ["git", "status", "--short"],
                workspaceRoot: workspaceRoot.path,
                summary: "inspect sandbox status",
                mutatesWorkspace: false
            ),
            testCommand: nil
        )

        let results = try await ParallelRunner().run(
            spec: spec,
            experimentsRoot: experimentsRoot,
            architectureRiskScore: 0
        )

        let metadata = try #require(results.first?.isolationMetadata)
        #expect(metadata.executionContext == "sandboxed-experiment")
        #expect(metadata.commitCoordinatorMutationAllowed == false)
        #expect(metadata.approvalPromotionAllowed == false)
        #expect(metadata.liveRuntimeMutationAllowed == false)
        #expect(metadata.candidatePaths == ["Sources/Sample.swift"])
        #expect(metadata.executedCommands.first?.summary == "inspect sandbox status")
        #expect(metadata.cleanupOutcome.removedWorktree == true)
    }

    private func makeGitWorkspace() -> URL {
        let workspaceRoot = makeTempDirectory().appendingPathComponent("workspace", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: workspaceRoot.appendingPathComponent("Sources", isDirectory: true),
            withIntermediateDirectories: true
        )
        try? "enum Sample { static let value = 1 }\n".write(
            to: workspaceRoot.appendingPathComponent("Sources/Sample.swift", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try? runGit(["init"], in: workspaceRoot)
        try? runGit(["config", "user.email", "oracle@example.com"], in: workspaceRoot)
        try? runGit(["config", "user.name", "Oracle Tests"], in: workspaceRoot)
        try? runGit(["add", "."], in: workspaceRoot)
        try? runGit(["commit", "-m", "initial"], in: workspaceRoot)
        return workspaceRoot
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = directory
        let stderr = Pipe()
        process.standardOutput = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "git failed"
            throw NSError(domain: "ExperimentIsolationTests", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}