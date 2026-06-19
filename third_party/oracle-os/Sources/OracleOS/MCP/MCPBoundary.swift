import Foundation

enum MCPBoundaryError: Error, LocalizedError {
    case missingToolName
    case invalidArgumentsShape
    case unsupportedValue(path: String)
    case encodingFailed(type: String)

    var errorDescription: String? {
        switch self {
        case .missingToolName:
            return "Missing tool name"
        case .invalidArgumentsShape:
            return "Invalid arguments payload"
        case .unsupportedValue(let path):
            return "Unsupported JSON value at \(path)"
        case .encodingFailed(let type):
            return "Failed to encode \(type)"
        }
    }
}

struct MCPCallRequest: Sendable {
    let name: String
    let arguments: MCPArguments
}

struct MCPArguments: Sendable {
    let values: [String: JSONValue]

    init(_ values: [String: JSONValue] = [:]) {
        self.values = values
    }

    func string(_ key: String) -> String? {
        guard case .string(let value)? = values[key] else {
            return nil
        }
        return value
    }

    func bool(_ key: String) -> Bool? {
        guard case .bool(let value)? = values[key] else {
            return nil
        }
        return value
    }

    func int(_ key: String) -> Int? {
        guard case .number(let value)? = values[key] else {
            return nil
        }
        return Int(value)
    }

    func double(_ key: String) -> Double? {
        guard case .number(let value)? = values[key] else {
            return nil
        }
        return value
    }

    func stringArray(_ key: String) -> [String]? {
        guard case .array(let values)? = values[key] else {
            return nil
        }

        var result: [String] = []
        result.reserveCapacity(values.count)
        for value in values {
            guard case .string(let string) = value else {
                return nil
            }
            result.append(string)
        }
        return result
    }

    func numberArray(_ key: String) -> [Double]? {
        guard case .array(let values)? = values[key] else {
            return nil
        }

        var result: [Double] = []
        result.reserveCapacity(values.count)
        for value in values {
            guard case .number(let number) = value else {
                return nil
            }
            result.append(number)
        }
        return result
    }

    func object(_ key: String) -> [String: JSONValue]? {
        guard case .object(let object)? = values[key] else {
            return nil
        }
        return object
    }

    func stringDictionary(_ key: String) -> [String: String]? {
        guard let object = object(key) else {
            return nil
        }

        var result: [String: String] = [:]
        result.reserveCapacity(object.count)
        for (name, value) in object {
            switch value {
            case .string(let string):
                result[name] = string
            case .number(let number):
                result[name] = String(number)
            case .bool(let boolean):
                result[name] = String(boolean)
            case .null:
                result[name] = "null"
            default:
                return nil
            }
        }
        return result
    }
}

struct MCPToolResultEnvelope: Encodable {
    let success: Bool
    let data: [String: JSONValue]?
    let error: String?
    let suggestion: String?
    let context: [String: JSONValue]?

    init(result: ToolResult) {
        success = result.success
        data = result.data.flatMap { JSONValue.from(any: $0)?.objectValue }
        error = result.error
        suggestion = result.suggestion
        context = result.context.flatMap { JSONValue.from(any: $0.toDict())?.objectValue }
    }
}

struct MCPTextContent: Encodable {
    let type = "text"
    let text: String
}

struct MCPImageContent: Encodable {
    let type = "image"
    let data: String
    let mimeType: String
}

struct MCPResponseEnvelope<Content: Encodable>: Encodable {
    let content: [Content]
    let isError: Bool
}

enum MCPBoundary {
    static func decodeCall(from params: [String: Any]) throws -> MCPCallRequest {
        guard let toolName = params["name"] as? String else {
            throw MCPBoundaryError.missingToolName
        }

        let arguments: MCPArguments
        if let rawArguments = params["arguments"] {
            guard let converted = try convert(rawArguments, path: "arguments"),
                  case .object(let object) = converted
            else {
                throw MCPBoundaryError.invalidArgumentsShape
            }
            arguments = MCPArguments(object)
        } else {
            arguments = MCPArguments()
        }

        return MCPCallRequest(name: toolName, arguments: arguments)
    }

    static func encodeResult(_ result: ToolResult, toolName: String) -> [String: Any] {
        let payload = MCPToolResultEnvelope(result: result)
        guard let json = jsonString(from: payload) else {
            return errorContent("Failed to serialize response for \(toolName)")
        }

        return rawResponse(
            MCPResponseEnvelope(content: [MCPTextContent(text: json)], isError: !result.success)
        ) ?? errorContent("Failed to serialize response for \(toolName)")
    }

    static func encodeImageResult(base64: String, mimeType: String, caption: String) -> [String: Any] {
        struct MCPMixedContent: Encodable {
            let type: String
            let data: String?
            let mimeType: String?
            let text: String?
        }

        let response = MCPResponseEnvelope(
            content: [
                MCPMixedContent(type: "image", data: base64, mimeType: mimeType, text: nil),
                MCPMixedContent(type: "text", data: nil, mimeType: nil, text: caption),
            ],
            isError: false
        )
        return rawResponse(response) ?? errorContent("Failed to serialize screenshot response")
    }

    static func errorContent(_ message: String) -> [String: Any] {
        struct MCPErrorContent: Encodable {
            let success: Bool
            let error: String
        }

        guard let json = jsonString(from: MCPErrorContent(success: false, error: message)) else {
            return [
                "content": [["type": "text", "text": "{\"success\":false,\"error\":\"serialization_failed\"}"]],
                "isError": true,
            ]
        }

        let response = MCPResponseEnvelope(
            content: [MCPTextContent(text: json)],
            isError: true
        )
        return rawResponse(response) ?? [
            "content": [["type": "text", "text": "{\"success\":false,\"error\":\"serialization_failed\"}"]],
            "isError": true,
        ]
    }

    static func makeToolResult<Payload: Encodable>(
        success: Bool = true,
        payload: Payload,
        error: String? = nil,
        suggestion: String? = nil,
        context: ContextInfo? = nil
    ) -> ToolResult {
        do {
            return try ToolResult(
                success: success,
                payload: payload,
                error: error,
                suggestion: suggestion,
                context: context
            )
        } catch {
            return ToolResult(success: false, error: MCPBoundaryError.encodingFailed(type: String(describing: Payload.self)).localizedDescription)
        }
    }

    static func exportDefinitions<T: Encodable>(from values: T) -> [[String: Any]]? {
        guard let object = rawObject(from: values) else {
            return nil
        }
        return object as? [[String: Any]]
    }

    private static func convert(_ value: Any, path: String) throws -> JSONValue? {
        if value is NSNull {
            return .null
        }
        if let converted = JSONValue.from(any: value) {
            return converted
        }
        throw MCPBoundaryError.unsupportedValue(path: path)
    }

    private static func jsonString<T: Encodable>(from value: T) -> String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func rawResponse<T: Encodable>(_ value: T) -> [String: Any]? {
        rawObject(from: value)
    }

    private static func rawObject<T: Encodable>(from value: T) -> [String: Any]? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value),
              let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dictionary = object as? [String: Any]
        else {
            return nil
        }
        return dictionary
    }
}