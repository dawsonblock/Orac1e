import Foundation

public struct CodingRetrievalRequest: Codable, Sendable {
    public let repoName: String
    public let repoPath: String
    public let query: String
    public let topK: Int
    public let paths: [String]?
    public let languages: [String]?
    public let refreshIndex: Bool

    enum CodingKeys: String, CodingKey {
        case repoName = "repo_name"
        case repoPath = "repo_path"
        case query, paths, languages
        case topK = "top_k"
        case refreshIndex = "refresh_index"
    }

    public init(
        repoName: String,
        repoPath: String,
        query: String,
        topK: Int = 10,
        paths: [String]? = nil,
        languages: [String]? = nil,
        refreshIndex: Bool = true
    ) {
        self.repoName = repoName
        self.repoPath = repoPath
        self.query = query
        self.topK = topK
        self.paths = paths
        self.languages = languages
        self.refreshIndex = refreshIndex
    }
}

public struct CodingRetrievalResult: Codable, Sendable, Identifiable {
    public let id: String
    public let path: String
    public let score: Double
    public let snippet: String
    public let startLine: Int
    public let endLine: Int
    public let language: String

    enum CodingKeys: String, CodingKey {
        case path, score, snippet, language
        case startLine = "start_line"
        case endLine = "end_line"
    }

    public init(
        path: String,
        score: Double,
        snippet: String,
        startLine: Int,
        endLine: Int,
        language: String
    ) {
        self.id = "\(path):\(startLine)-\(endLine)"
        self.path = path
        self.score = score
        self.snippet = snippet
        self.startLine = startLine
        self.endLine = endLine
        self.language = language
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let path = try container.decode(String.self, forKey: .path)
        let score = try container.decode(Double.self, forKey: .score)
        let snippet = try container.decode(String.self, forKey: .snippet)
        let startLine = try container.decode(Int.self, forKey: .startLine)
        let endLine = try container.decode(Int.self, forKey: .endLine)
        let language = try container.decode(String.self, forKey: .language)

        self.id = "\(path):\(startLine)-\(endLine)"
        self.path = path
        self.score = score
        self.snippet = snippet
        self.startLine = startLine
        self.endLine = endLine
        self.language = language
    }
}

public struct CodingRetrievalResponse: Codable, Sendable {
    public let status: String
    public let results: [CodingRetrievalResult]
    public let message: String?
}
