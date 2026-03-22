import Foundation

enum ToolKind: String, Codable {
    case worker
    case retrieval
    case validator
    case action
}

enum ToolRiskLevel: String, Codable {
    case low
    case medium
    case high
}

struct ToolTimeouts: Codable {
    let healthMs: Int
    let invokeMs: Int

    enum CodingKeys: String, CodingKey {
        case healthMs = "health_ms"
        case invokeMs = "invoke_ms"
    }
}

struct ToolConcurrency: Codable {
    let maxGlobal: Int
    let maxPerRepo: Int

    enum CodingKeys: String, CodingKey {
        case maxGlobal = "max_global"
        case maxPerRepo = "max_per_repo"
    }
}

struct ToolFeatures: Codable {
    let supportsDiff: Bool
    let supportsStreaming: Bool
    let supportsCancellation: Bool

    enum CodingKeys: String, CodingKey {
        case supportsDiff = "supports_diff"
        case supportsStreaming = "supports_streaming"
        case supportsCancellation = "supports_cancellation"
    }
}

struct ToolManifest: Codable {
    let id: String
    let name: String
    let version: String
    let apiVersion: String
    let kind: ToolKind
    let capabilities: [String]
    let baseURL: String
    let healthPath: String
    let invokePath: String
    let riskLevel: ToolRiskLevel
    let repoLanguages: [String]
    let timeouts: ToolTimeouts
    let concurrency: ToolConcurrency
    let features: ToolFeatures

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
