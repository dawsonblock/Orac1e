import Foundation

public struct CodingRunMetadata: Codable, Sendable {
    public let runID: String
    public let canonicalRepoPath: String
    public let worktreePath: String
    public let validationCommands: [String]
    public let validationProfileName: String?
    public let allowedPaths: [String]
    public let retrievalQuery: String
    public let workerMode: CodingRunMode
    public let createdAt: Date

    public init(
        runID: String,
        canonicalRepoPath: String,
        worktreePath: String,
        validationCommands: [String],
        validationProfileName: String? = nil,
        allowedPaths: [String],
        retrievalQuery: String,
        workerMode: CodingRunMode,
        createdAt: Date = Date()
    ) {
        self.runID = runID
        self.canonicalRepoPath = canonicalRepoPath
        self.worktreePath = worktreePath
        self.validationCommands = validationCommands
        self.validationProfileName = validationProfileName
        self.allowedPaths = allowedPaths
        self.retrievalQuery = retrievalQuery
        self.workerMode = workerMode
        self.createdAt = createdAt
    }
}

public actor RunMetadataStore {
    private let baseURL: URL
    private let encoder = JSONEncoder()

    public init(baseURL: URL) {
        self.baseURL = baseURL.appendingPathComponent("metadata", isDirectory: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
    }

    public func put(_ metadata: CodingRunMetadata) throws {
        try FileManager.default.createDirectory(
            at: baseURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let fileURL = baseURL.appendingPathComponent("\(metadata.runID).json")
        let data = try encoder.encode(metadata)
        try data.write(to: fileURL)
    }
}
