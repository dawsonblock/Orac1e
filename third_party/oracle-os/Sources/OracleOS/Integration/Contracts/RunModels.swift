import Foundation

public enum CodingRunMode: String, Codable, Sendable {
    case interactive
    case autonomous
}

public enum CodingRunStatus: String, Codable, Sendable {
    case created
    case retrieving
    case proposing
    case validating
    case applied
    case rejected
    case failed
    case awaitingApproval = "awaiting_approval"
}

public struct CodingRunRecord: Codable, Sendable, Identifiable {
    public let id: String
    public let repoName: String
    public let repoPath: String
    public let mode: CodingRunMode
    public var status: CodingRunStatus
    public let task: String
    public let createdAt: Date

    public init(
        id: String,
        repoName: String,
        repoPath: String,
        mode: CodingRunMode,
        status: CodingRunStatus,
        task: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.repoName = repoName
        self.repoPath = repoPath
        self.mode = mode
        self.status = status
        self.task = task
        self.createdAt = createdAt
    }
}

public struct CodingRunEvent: Codable, Sendable, Identifiable {
    public let id: String
    public let runID: String
    public let type: String
    public let ts: Date
    public let payload: [String: String]

    public init(
        id: String = UUID().uuidString,
        runID: String,
        type: String,
        ts: Date = Date(),
        payload: [String: String] = [:]
    ) {
        self.id = id
        self.runID = runID
        self.type = type
        self.ts = ts
        self.payload = payload
    }
}
