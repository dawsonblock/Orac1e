import Foundation

public actor CodingWorktreeCoordinator {
    private let workspaceRoot: URL

    public init(workspaceRoot: URL) {
        self.workspaceRoot = workspaceRoot
    }

    public func worktreeURL(for runID: String) -> URL {
        workspaceRoot
            .appendingPathComponent("worktrees", isDirectory: true)
            .appendingPathComponent(runID, isDirectory: true)
    }

    public func createWorktree(runID: String, sourceRepoURL: URL, baseRef: String = "HEAD") throws -> URL {
        let fileManager = FileManager.default
        let target = worktreeURL(for: runID)
        try fileManager.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        if fileManager.fileExists(atPath: target.path) {
            return target
        }
        try CodingShell.run(["git", "-C", sourceRepoURL.path, "worktree", "add", "--detach", target.path, baseRef])
        return target
    }

    public func removeWorktree(runID: String, sourceRepoURL: URL) throws {
        let target = worktreeURL(for: runID)
        guard FileManager.default.fileExists(atPath: target.path) else {
            return
        }
        try CodingShell.run(["git", "-C", sourceRepoURL.path, "worktree", "remove", "--force", target.path])
    }
}

public enum CodingShell {
    @discardableResult
    public static func run(_ argv: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = argv

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "CodingShell",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: stderr]
            )
        }
        return stdout
    }
}
