import Foundation

public enum WorkspaceRunnerError: Error, LocalizedError, Sendable, Equatable {
    case unsupportedCommand(String)
    case scopeViolation(String)
    case forbiddenGitOperation(String)
    case networkNotAllowed(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedCommand(summary):
            "Unsupported command: \(summary)"
        case let .scopeViolation(message):
            message
        case let .forbiddenGitOperation(detail):
            "Forbidden git operation: \(detail)"
        case let .networkNotAllowed(detail):
            "Network access not allowed: \(detail)"
        }
    }
}

/// Classifies git subcommands by their access level.
public enum GitAccessLevel: Sendable {
    /// Read-only operations that never mutate the repo or touch the network.
    case readOnly
    /// Local write operations that mutate the working tree or index but do not contact remotes.
    case localWrite
    /// Network operations that contact remote servers.
    case network
}

public final class WorkspaceRunner: @unchecked Sendable {
    public init() {}

    public func execute(spec: CommandSpec) throws -> CommandResult {
        guard isAllowed(spec) else {
            throw WorkspaceRunnerError.unsupportedCommand(spec.summary)
        }

        try validateGitPolicy(spec)

        // Derive network access from the command structure rather than trusting
        // the touchesNetwork field on CommandSpec.
        if derivedTouchesNetwork(spec) {
            throw WorkspaceRunnerError.networkNotAllowed(
                "Command \(spec.category.rawValue) requires network access which is not permitted"
            )
        }

        let scope = try WorkspaceScope(rootURL: URL(fileURLWithPath: spec.workspaceRoot, isDirectory: true))
        _ = try scope.resolve(relativePath: spec.workspaceRelativePath)

        let start = Date()
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: spec.executable)
        process.arguments = spec.arguments
        process.currentDirectoryURL = scope.rootURL
        process.standardOutput = stdout
        process.standardError = stderr
        process.environment = sanitizedEnvironment()

        try process.run()
        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()

        return CommandResult(
            succeeded: process.terminationStatus == 0,
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? "",
            elapsedMs: Date().timeIntervalSince(start) * 1000.0,
            workspaceRoot: spec.workspaceRoot,
            category: spec.category,
            summary: spec.summary
        )
    }

    // MARK: - Git Subcommand Policy

    /// Allowed git subcommands and their access levels. Subcommands not in this
    /// map are rejected.
    static let gitSubcommandPolicy: [String: GitAccessLevel] = [
        "status": .readOnly,
        "log": .readOnly,
        "diff": .readOnly,
        "show": .readOnly,
        "branch": .readOnly,
        "rev-parse": .readOnly,
        "ls-files": .readOnly,
        "blame": .readOnly,
        "stash": .localWrite,
        "add": .localWrite,
        "commit": .localWrite,
        "checkout": .localWrite,
        "switch": .localWrite,
        "merge": .localWrite,
        "rebase": .localWrite,
        "reset": .localWrite,
        "restore": .localWrite,
        "tag": .localWrite,
        "push": .network,
        "pull": .network,
        "fetch": .network,
        "clone": .network,
        "remote": .network,
    ]

    /// Flags that are never allowed on any git subcommand.
    static let forbiddenGitFlags: Set<String> = [
        "--force", "-f",
        "--force-with-lease",
        "--mirror",
        "--bare",
        "--delete",
        "--prune-tags",
    ]

    /// Parse the git subcommand from arguments (skipping global flags like -C, -c).
    static func parseGitSubcommand(from arguments: [String]) -> String? {
        var i = 0
        while i < arguments.count {
            let arg = arguments[i]
            // Skip global git flags that take a value
            if arg == "-C" || arg == "-c" || arg == "--git-dir" || arg == "--work-tree" {
                i += 2
                continue
            }
            // Skip global boolean flags
            if arg.hasPrefix("-") {
                i += 1
                continue
            }
            return arg
        }
        return nil
    }

    /// Validate that a git command conforms to the structured policy.
    private func validateGitPolicy(_ spec: CommandSpec) throws {
        guard spec.category.isGit else { return }

        guard let subcommand = Self.parseGitSubcommand(from: spec.arguments) else {
            throw WorkspaceRunnerError.forbiddenGitOperation("could not parse git subcommand")
        }

        guard Self.gitSubcommandPolicy[subcommand] != nil else {
            throw WorkspaceRunnerError.forbiddenGitOperation(
                "git subcommand '\(subcommand)' is not in the allowed set"
            )
        }

        // Check for forbidden flags
        for arg in spec.arguments where arg.hasPrefix("-") {
            // Treat an argument as forbidden if it:
            //  - exactly matches a forbidden flag (e.g. "--force-with-lease")
            //  - or starts with "<forbidden-flag>=" (e.g. "--force-with-lease=origin/main")
            //  - or, for single-character short flags (e.g. "-f"), appears in a combined
            //    short flag group (e.g. "-fn")
            for forbidden in Self.forbiddenGitFlags {
                if arg == forbidden || arg.hasPrefix(forbidden + "=") {
                    throw WorkspaceRunnerError.forbiddenGitOperation(
                        "flag '\(arg)' is forbidden on git commands"
                    )
                }

                // Handle combined short flags like "-fn" when "-f" is forbidden.
                if forbidden.hasPrefix("-"),
                   !forbidden.hasPrefix("--"),
                   forbidden.count == 2,
                   arg.hasPrefix("-"),
                   arg.count > 2 {
                    let shortFlagChar = forbidden.dropFirst()
                    if arg.dropFirst().contains(shortFlagChar) {
                        throw WorkspaceRunnerError.forbiddenGitOperation(
                            "flag '\(arg)' is forbidden on git commands"
                        )
                    }
                }
            }
        }
    }

    /// Derive whether a command touches the network from its structure, rather
    /// than trusting the `touchesNetwork` field on CommandSpec.
    func derivedTouchesNetwork(_ spec: CommandSpec) -> Bool {
        guard spec.category.isGit else { return false }
        guard let subcommand = Self.parseGitSubcommand(from: spec.arguments) else {
            return false
        }
        return Self.gitSubcommandPolicy[subcommand] == .network
    }

    private func isAllowed(_ spec: CommandSpec) -> Bool {
        switch spec.category {
        case .build, .test, .formatter, .linter, .gitStatus, .gitBranch, .gitCommit, .gitPush:
            return allowedExecutable(spec.executable)
        case .indexRepository, .searchCode, .openFile, .editFile, .writeFile, .generatePatch, .parseBuildFailure, .parseTestFailure:
            return true
        }
    }

    private func allowedExecutable(_ executable: String) -> Bool {
        let allowedExecutables = [
            "/usr/bin/env",
            "/usr/bin/git",
        ]
        return allowedExecutables.contains(executable)
    }

    private func sanitizedEnvironment() -> [String: String] {
        let source = ProcessInfo.processInfo.environment
        let keys = ["PATH", "HOME", "LANG", "LC_ALL", "TMPDIR", "DEVELOPER_DIR"]
        return Dictionary(uniqueKeysWithValues: keys.compactMap { key in
            source[key].map { (key, $0) }
        })
    }
}
