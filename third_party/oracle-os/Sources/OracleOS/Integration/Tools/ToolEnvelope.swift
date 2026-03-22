import Foundation

struct ToolInvokeEnvelope: Codable {
    let contractVersion: String
    let runID: String
    let toolID: String
    let capability: String
    let payload: [String: JSONValue]
    let constraints: [String: JSONValue]
    let context: [String: JSONValue]
    let metadata: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case runID = "run_id"
        case toolID = "tool_id"
        case capability, payload, constraints, context, metadata
    }
}

struct ToolResponseEnvelope: Codable {
    let contractVersion: String
    let status: String
    let toolID: String
    let capability: String
    let summary: String
    let payload: [String: JSONValue]
    let warnings: [String]
    let artifacts: [String]
    let metrics: [String: JSONValue]
    let error: String?

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case status
        case toolID = "tool_id"
        case capability, summary, payload, warnings, artifacts, metrics, error
    }
}
