import Foundation

public struct FixPattern: Codable, Sendable, Equatable {
    public let errorSignature: String
    public let workspaceRelativePath: String?
    public let commandCategory: String
    public let successCount: Int
    public let failureCount: Int
    public let lastAppliedAt: Date

    public init(
        errorSignature: String,
        workspaceRelativePath: String?,
        commandCategory: String,
        successCount: Int = 0,
        failureCount: Int = 0,
        lastAppliedAt: Date = Date()
    ) {
        self.errorSignature = errorSignature
        self.workspaceRelativePath = workspaceRelativePath
        self.commandCategory = commandCategory
        self.successCount = successCount
        self.failureCount = failureCount
        self.lastAppliedAt = lastAppliedAt
    }

    public var failureRate: Double {
        let total = successCount + failureCount
        guard total > 0 else { return 0 }
        return Double(failureCount) / Double(total)
    }
}
