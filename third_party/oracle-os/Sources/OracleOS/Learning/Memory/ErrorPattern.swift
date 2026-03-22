import Foundation

public struct ErrorPattern: Codable, Sendable, Equatable, Hashable {
    public let signature: String
    public let category: String
    public let workspaceRoot: String
    public let timestamp: Date

    public init(signature: String, category: String, workspaceRoot: String, timestamp: Date = Date()) {
        self.signature = signature
        self.category = category
        self.workspaceRoot = workspaceRoot
        self.timestamp = timestamp
    }
}
