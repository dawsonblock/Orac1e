import Foundation

public struct WorktreeSandbox: Codable, Sendable, Equatable {
    public let experimentID: String
    public let candidateID: String
    public let workspaceRoot: String
    public let experimentsRoot: String
    public let sandboxPath: String
    public let canonicalWorkspaceRoot: String
    public let canonicalSandboxPath: String
    public let branchName: String

    public init(
        experimentID: String,
        candidateID: String,
        workspaceRoot: String,
        experimentsRoot: String,
        sandboxPath: String,
        canonicalWorkspaceRoot: String,
        canonicalSandboxPath: String,
        branchName: String
    ) {
        self.experimentID = experimentID
        self.candidateID = candidateID
        self.workspaceRoot = workspaceRoot
        self.experimentsRoot = experimentsRoot
        self.sandboxPath = sandboxPath
        self.canonicalWorkspaceRoot = canonicalWorkspaceRoot
        self.canonicalSandboxPath = canonicalSandboxPath
        self.branchName = branchName
    }

    public static func create(
        experimentID: String,
        candidateID: String,
        workspaceRoot: URL,
        experimentsRoot: URL
    ) throws -> WorktreeSandbox {
        try FileManager.default.createDirectory(at: experimentsRoot, withIntermediateDirectories: true)
        let canonicalWorkspaceRoot = try canonicalDirectoryURL(for: workspaceRoot)
        let canonicalExperimentsRoot = experimentsRoot.standardizedFileURL
        try ensureContained(child: canonicalExperimentsRoot, within: canonicalWorkspaceRoot, label: "experiments root")

        let sandboxPath = experimentsRoot
            .appendingPathComponent(experimentID, isDirectory: true)
            .appendingPathComponent(candidateID, isDirectory: true)
        try FileManager.default.createDirectory(at: sandboxPath.deletingLastPathComponent(), withIntermediateDirectories: true)

        let branchName = "codex/exp-\(experimentID)-\(candidateID)"
        try runGit(arguments: ["worktree", "add", "-f", "-b", branchName, sandboxPath.path, "HEAD"], workspaceRoot: workspaceRoot)
        let canonicalSandboxPath = try canonicalDirectoryURL(for: sandboxPath)
        try ensureContained(child: canonicalSandboxPath, within: canonicalExperimentsRoot, label: "sandbox root")

        return WorktreeSandbox(
            experimentID: experimentID,
            candidateID: candidateID,
            workspaceRoot: workspaceRoot.path,
            experimentsRoot: experimentsRoot.path,
            sandboxPath: sandboxPath.path,
            canonicalWorkspaceRoot: canonicalWorkspaceRoot.path,
            canonicalSandboxPath: canonicalSandboxPath.path,
            branchName: branchName
        )
    }

    public func apply(_ candidate: CandidatePatch) throws {
        let fileURL = try resolveCandidateFileURL(candidate.workspaceRelativePath)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try candidate.content.write(to: fileURL, atomically: true, encoding: .utf8)
        let canonicalParent = try canonicalDirectoryURL(for: fileURL.deletingLastPathComponent())
        try ensureContained(
            child: canonicalParent,
            within: URL(fileURLWithPath: canonicalSandboxPath, isDirectory: true),
            label: "candidate parent"
        )
    }

    public func diffSummary() -> String {
        (try? runGitOutput(arguments: ["diff", "--stat"], workspaceRoot: URL(fileURLWithPath: sandboxPath, isDirectory: true))) ?? ""
    }

    public func cleanup() -> SandboxCleanupOutcome {
        var errors: [String] = []
        let workspaceURL = URL(fileURLWithPath: workspaceRoot, isDirectory: true)

        let removedWorktree: Bool
        do {
            try runGit(arguments: ["worktree", "remove", "--force", sandboxPath], workspaceRoot: workspaceURL)
            removedWorktree = true
        } catch {
            removedWorktree = false
            errors.append(error.localizedDescription)
        }

        let removedBranch: Bool
        do {
            try runGit(arguments: ["branch", "-D", branchName], workspaceRoot: workspaceURL)
            removedBranch = true
        } catch {
            removedBranch = false
            errors.append(error.localizedDescription)
        }

        return SandboxCleanupOutcome(
            removedWorktree: removedWorktree,
            removedBranch: removedBranch,
            errors: errors
        )
    }

    public func resolveCandidateFileURL(_ workspaceRelativePath: String) throws -> URL {
        guard !workspaceRelativePath.hasPrefix("/") else {
            throw sandboxError("Candidate path must be workspace-relative: \(workspaceRelativePath)")
        }

        let pathComponents = NSString(string: workspaceRelativePath).pathComponents
        guard !pathComponents.contains("..") else {
            throw sandboxError("Candidate path may not traverse outside sandbox: \(workspaceRelativePath)")
        }

        let sandboxRootURL = URL(fileURLWithPath: canonicalSandboxPath, isDirectory: true)
        let targetURL = pathComponents.reduce(sandboxRootURL) { partialResult, component in
            partialResult.appendingPathComponent(component, isDirectory: false)
        }
        let standardizedTarget = targetURL.standardizedFileURL
        try ensureContained(child: standardizedTarget, within: sandboxRootURL, label: "candidate path")
        return standardizedTarget
    }
}

private func canonicalDirectoryURL(for url: URL) throws -> URL {
    if FileManager.default.fileExists(atPath: url.path) {
        return url.resolvingSymlinksInPath().standardizedFileURL
    }

    let parent = url.deletingLastPathComponent()
    let canonicalParent = try canonicalDirectoryURL(for: parent)
    return canonicalParent.appendingPathComponent(url.lastPathComponent, isDirectory: true).standardizedFileURL
}

private func ensureContained(child: URL, within root: URL, label: String) throws {
    let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
    let childPath = child.path.hasSuffix("/") ? child.path : child.path + "/"
    guard childPath.hasPrefix(rootPath) || child.path == root.path else {
        throw sandboxError("\(label) escaped sandbox containment: \(child.path)")
    }
}

private func sandboxError(_ message: String) -> NSError {
    NSError(
        domain: "WorktreeSandbox",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: message]
    )
}

private func runGit(arguments: [String], workspaceRoot: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git"] + arguments
    process.currentDirectoryURL = workspaceRoot
    let stderr = Pipe()
    process.standardError = stderr
    process.standardOutput = Pipe()
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "git worktree failed"
        throw NSError(domain: "WorktreeSandbox", code: Int(process.terminationStatus), userInfo: [
            NSLocalizedDescriptionKey: message.trimmingCharacters(in: .whitespacesAndNewlines),
        ])
    }
}

private func runGitOutput(arguments: [String], workspaceRoot: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git"] + arguments
    process.currentDirectoryURL = workspaceRoot
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "git worktree failed"
        throw NSError(domain: "WorktreeSandbox", code: Int(process.terminationStatus), userInfo: [
            NSLocalizedDescriptionKey: message.trimmingCharacters(in: .whitespacesAndNewlines),
        ])
    }
    return String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}
