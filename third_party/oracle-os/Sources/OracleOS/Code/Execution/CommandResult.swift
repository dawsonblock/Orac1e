import Foundation

public struct CommandResult: Codable, Sendable, Equatable {
    public let succeeded: Bool
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let elapsedMs: Double
    public let workspaceRoot: String
    public let category: CodeCommandCategory
    public let summary: String

    public init(
        succeeded: Bool,
        exitCode: Int32,
        stdout: String,
        stderr: String,
        elapsedMs: Double,
        workspaceRoot: String,
        category: CodeCommandCategory,
        summary: String
    ) {
        self.succeeded = succeeded
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.elapsedMs = elapsedMs
        self.workspaceRoot = workspaceRoot
        self.category = category
        self.summary = summary
    }
}
