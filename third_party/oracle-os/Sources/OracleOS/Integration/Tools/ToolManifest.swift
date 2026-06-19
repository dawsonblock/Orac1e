import Foundation

public enum ToolKind: String, Codable, Sendable {
    case worker
    case retrieval
    case validator
    case action
}

public enum ToolRiskLevel: String, Codable, Sendable {
    case low
    case medium
    case high
}

public struct ToolTimeouts: Codable, Sendable {
    public let healthMs: Int
    public let invokeMs: Int

    enum CodingKeys: String, CodingKey {
        case healthMs = "health_ms"
        case invokeMs = "invoke_ms"
    }
}

public struct ToolConcurrency: Codable, Sendable {
    public let maxGlobal: Int
    public let maxPerRepo: Int

    enum CodingKeys: String, CodingKey {
        case maxGlobal = "max_global"
        case maxPerRepo = "max_per_repo"
    }
}

public struct ToolFeatures: Codable, Sendable {
    public let supportsDiff: Bool
    public let supportsStreaming: Bool
    public let supportsCancellation: Bool

    enum CodingKeys: String, CodingKey {
        case supportsDiff = "supports_diff"
        case supportsStreaming = "supports_streaming"
        case supportsCancellation = "supports_cancellation"
    }
}

public struct ToolManifest: Codable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let apiVersion: String
    public let kind: ToolKind
    public let capabilities: [String]
    public let baseURL: String
    public let healthPath: String
    public let invokePath: String
    public let riskLevel: ToolRiskLevel
    public let repoLanguages: [String]
    public let timeouts: ToolTimeouts
    public let concurrency: ToolConcurrency
    public let features: ToolFeatures

    enum CodingKeys: String, CodingKey {
        case id, name, version, kind, capabilities, timeouts, concurrency, features
        case apiVersion = "api_version"
        case baseURL = "base_url"
        case healthPath = "health_path"
        case invokePath = "invoke_path"
        case riskLevel = "risk_level"
        case repoLanguages = "repo_languages"
    }
}
