import Foundation
import Testing
@testable import OracleOS

@Suite("WorkspaceRunner Command Policy")
struct WorkspaceRunnerCommandPolicyTests {

    // MARK: - Git Subcommand Parsing

    @Test("Parses git subcommand from simple arguments")
    func parsesSimpleSubcommand() {
        #expect(WorkspaceRunner.parseGitSubcommand(from: ["status"]) == "status")
        #expect(WorkspaceRunner.parseGitSubcommand(from: ["commit", "-m", "msg"]) == "commit")
        #expect(WorkspaceRunner.parseGitSubcommand(from: ["push", "origin", "main"]) == "push")
        #expect(WorkspaceRunner.parseGitSubcommand(from: ["log", "--oneline"]) == "log")
    }

    @Test("Parses git subcommand skipping global flags")
    func parsesSubcommandSkippingGlobalFlags() {
        #expect(WorkspaceRunner.parseGitSubcommand(from: ["-C", "/tmp", "status"]) == "status")
        #expect(WorkspaceRunner.parseGitSubcommand(from: ["-c", "user.name=test", "commit", "-m", "msg"]) == "commit")
        #expect(WorkspaceRunner.parseGitSubcommand(from: ["--git-dir", "/repo", "log"]) == "log")
    }

    @Test("Returns nil for empty arguments")
    func returnsNilForEmpty() {
        #expect(WorkspaceRunner.parseGitSubcommand(from: []) == nil)
        #expect(WorkspaceRunner.parseGitSubcommand(from: ["--verbose"]) == nil)
    }

    // MARK: - Git Access Level Policy

    @Test("Read-only git subcommands are classified correctly")
    func readOnlyGitSubcommands() {
        let readOnlyCommands = ["status", "log", "diff", "show", "branch", "rev-parse", "ls-files", "blame"]
        for cmd in readOnlyCommands {
            #expect(WorkspaceRunner.gitSubcommandPolicy[cmd] == .readOnly,
                    "Expected \(cmd) to be readOnly")
        }
    }

    @Test("Local write git subcommands are classified correctly")
    func localWriteGitSubcommands() {
        let writeCommands = ["add", "commit", "checkout", "switch", "merge", "rebase", "reset", "restore", "tag", "stash"]
        for cmd in writeCommands {
            #expect(WorkspaceRunner.gitSubcommandPolicy[cmd] == .localWrite,
                    "Expected \(cmd) to be localWrite")
        }
    }

    @Test("Network git subcommands are classified correctly")
    func networkGitSubcommands() {
        let networkCommands = ["push", "pull", "fetch", "clone", "remote"]
        for cmd in networkCommands {
            #expect(WorkspaceRunner.gitSubcommandPolicy[cmd] == .network,
                    "Expected \(cmd) to be network")
        }
    }

    // MARK: - Forbidden Flags

    @Test("Forbidden git flags are present in the policy")
    func forbiddenGitFlagsExist() {
        #expect(WorkspaceRunner.forbiddenGitFlags.contains("--force"))
        #expect(WorkspaceRunner.forbiddenGitFlags.contains("-f"))
        #expect(WorkspaceRunner.forbiddenGitFlags.contains("--force-with-lease"))
        #expect(WorkspaceRunner.forbiddenGitFlags.contains("--mirror"))
        #expect(WorkspaceRunner.forbiddenGitFlags.contains("--delete"))
    }

    // MARK: - Network Derivation

    @Test("derivedTouchesNetwork returns true for network git commands")
    func derivedNetworkForPush() {
        let runner = WorkspaceRunner()
        let pushSpec = CommandSpec(
            category: .gitPush,
            executable: "/usr/bin/git",
            arguments: ["push", "origin", "main"],
            workspaceRoot: "/tmp",
            summary: "push to remote"
        )
        #expect(runner.derivedTouchesNetwork(pushSpec) == true)
    }

    @Test("derivedTouchesNetwork returns false for local git commands")
    func derivedNetworkForStatus() {
        let runner = WorkspaceRunner()
        let statusSpec = CommandSpec(
            category: .gitStatus,
            executable: "/usr/bin/git",
            arguments: ["status"],
            workspaceRoot: "/tmp",
            summary: "git status"
        )
        #expect(runner.derivedTouchesNetwork(statusSpec) == false)
    }

    @Test("derivedTouchesNetwork returns false for non-git commands")
    func derivedNetworkForBuild() {
        let runner = WorkspaceRunner()
        let buildSpec = CommandSpec(
            category: .build,
            executable: "/usr/bin/env",
            arguments: ["swift", "build"],
            workspaceRoot: "/tmp",
            summary: "swift build"
        )
        #expect(runner.derivedTouchesNetwork(buildSpec) == false)
    }

    // MARK: - Error Types

    @Test("WorkspaceRunnerError has all expected cases")
    func errorCasesExist() {
        let unsupported = WorkspaceRunnerError.unsupportedCommand("test")
        let scope = WorkspaceRunnerError.scopeViolation("test")
        let forbidden = WorkspaceRunnerError.forbiddenGitOperation("test")
        let network = WorkspaceRunnerError.networkNotAllowed("test")

        #expect(unsupported.errorDescription?.contains("Unsupported") == true)
        #expect(scope.errorDescription != nil)
        #expect(forbidden.errorDescription?.contains("Forbidden") == true)
        #expect(network.errorDescription?.contains("Network") == true)
    }
}
