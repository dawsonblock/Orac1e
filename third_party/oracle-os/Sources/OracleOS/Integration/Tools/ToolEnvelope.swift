import Foundation

public struct ToolInvokeEnvelope: Codable, Sendable {
    public let contractVersion: String
    public let runID: String
    public let toolID: String
    public let capability: String
    public let payload: [String: JSONValue]
    public let constraints: [String: JSONValue]
    public let context: [String: JSONValue]
    public let metadata: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case runID = "run_id"
        case toolID = "tool_id"
        case capability, payload, constraints, context, metadata
    }
}

public struct ToolResponseEnvelope: Codable, Sendable {
    public let contractVersion: String
    public let status: String
    public let toolID: String
    public let capability: String
    public let summary: String
    public let payload: [String: JSONValue]
    public let warnings: [String]
    public let artifacts: [String]
    public let metrics: [String: JSONValue]
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case status
        case toolID = "tool_id"
        case capability, summary, payload, warnings, artifacts, metrics, error
    }
}
