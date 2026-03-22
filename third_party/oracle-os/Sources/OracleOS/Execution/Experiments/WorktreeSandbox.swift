import Foundation

public struct WorktreeSandbox: Codable, Sendable, Equatable {
    public let experimentID: String
    public let candidateID: String
    public let workspaceRoot: String
    public let sandboxPath: String
    public let branchName: String

    public init(
        experimentID: String,
        candidateID: String,
        workspaceRoot: String,
        sandboxPath: String,
        branchName: String
    ) {
        self.experimentID = experimentID
        self.candidateID = candidateID
        self.workspaceRoot = workspaceRoot
        self.sandboxPath = sandboxPath
        self.branchName = branchName
    }

    public static func create(
        experimentID: String,
        candidateID: String,
        workspaceRoot: URL,
        experimentsRoot: URL
    ) throws -> WorktreeSandbox {
        try FileManager.default.createDirectory(at: experimentsRoot, withIntermediateDirectories: true)
        let sandboxPath = experimentsRoot
            .appendingPathComponent(experimentID, isDirectory: true)
            .appendingPathComponent(candidateID, isDirectory: true)
        try FileManager.default.createDirectory(at: sandboxPath.deletingLastPathComponent(), withIntermediateDirectories: true)

        let branchName = "codex/exp-\(experimentID)-\(candidateID)"
        try runGit(arguments: ["worktree", "add", "-f", "-b", branchName, sandboxPath.path, "HEAD"], workspaceRoot: workspaceRoot)

        return WorktreeSandbox(
            experimentID: experimentID,
            candidateID: candidateID,
            workspaceRoot: workspaceRoot.path,
            sandboxPath: sandboxPath.path,
            branchName: branchName
        )
    }

    public func apply(_ candidate: CandidatePatch) throws {
        let fileURL = URL(fileURLWithPath: sandboxPath, isDirectory: true)
            .appendingPathComponent(candidate.workspaceRelativePath, isDirectory: false)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try candidate.content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    public func diffSummary() -> String {
        (try? runGitOutput(arguments: ["diff", "--stat"], workspaceRoot: URL(fileURLWithPath: sandboxPath, isDirectory: true))) ?? ""
    }

    public func cleanup() {
        try? runGit(arguments: ["worktree", "remove", "--force", sandboxPath], workspaceRoot: URL(fileURLWithPath: workspaceRoot, isDirectory: true))
        try? runGit(arguments: ["branch", "-D", branchName], workspaceRoot: URL(fileURLWithPath: workspaceRoot, isDirectory: true))
    }
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
