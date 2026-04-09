import Foundation

public struct ClaudeConfig: Codable, Sendable, Equatable {
    public var mcpServers: [String: ClaudeMCPServer]
    public var allowedTools: [String]?
    public var additionalFields: [String: JSONValue]

    public init(
        mcpServers: [String: ClaudeMCPServer] = [:],
        allowedTools: [String]? = nil,
        additionalFields: [String: JSONValue] = [:]
    ) {
        self.mcpServers = mcpServers
        self.allowedTools = allowedTools
        self.additionalFields = additionalFields
    }

    enum CodingKeys: String, CodingKey {
        case mcpServers
        case allowedTools
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        mcpServers = try container.decodeIfPresent([String: ClaudeMCPServer].self, forKey: DynamicCodingKey("mcpServers")) ?? [:]
        allowedTools = try container.decodeIfPresent([String].self, forKey: DynamicCodingKey("allowedTools"))

        let knownKeys = Set([CodingKeys.mcpServers.rawValue, CodingKeys.allowedTools.rawValue])
        var extras: [String: JSONValue] = [:]
        for key in container.allKeys where !knownKeys.contains(key.stringValue) {
            extras[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        additionalFields = extras
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        if !mcpServers.isEmpty {
            try container.encode(mcpServers, forKey: DynamicCodingKey("mcpServers"))
        }
        if let allowedTools {
            try container.encode(allowedTools, forKey: DynamicCodingKey("allowedTools"))
        }
        for (key, value) in additionalFields {
            try container.encode(value, forKey: DynamicCodingKey(key))
        }
    }

    public func server(named name: String) -> ClaudeMCPServer? {
        mcpServers[name]
    }

    public func withServer(named name: String, server: ClaudeMCPServer) -> ClaudeConfig {
        var copy = self
        copy.mcpServers[name] = server
        return copy
    }

    public func withAllowedTool(_ tool: String) -> ClaudeConfig {
        var copy = self
        var values = copy.allowedTools ?? []
        if !values.contains(tool) {
            values.append(tool)
        }
        copy.allowedTools = values.sorted()
        return copy
    }
}

public struct ClaudeMCPServer: Codable, Sendable, Equatable {
    public var type: String
    public var command: String
    public var args: [String]
    public var additionalFields: [String: JSONValue]

    public init(
        type: String,
        command: String,
        args: [String],
        additionalFields: [String: JSONValue] = [:]
    ) {
        self.type = type
        self.command = command
        self.args = args
        self.additionalFields = additionalFields
    }

    enum CodingKeys: String, CodingKey {
        case type
        case command
        case args
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        type = try container.decode(String.self, forKey: DynamicCodingKey("type"))
        command = try container.decode(String.self, forKey: DynamicCodingKey("command"))
        args = try container.decodeIfPresent([String].self, forKey: DynamicCodingKey("args")) ?? []

        let knownKeys = Set([CodingKeys.type.rawValue, CodingKeys.command.rawValue, CodingKeys.args.rawValue])
        var extras: [String: JSONValue] = [:]
        for key in container.allKeys where !knownKeys.contains(key.stringValue) {
            extras[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        additionalFields = extras
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(type, forKey: DynamicCodingKey("type"))
        try container.encode(command, forKey: DynamicCodingKey("command"))
        if !args.isEmpty {
            try container.encode(args, forKey: DynamicCodingKey("args"))
        }
        for (key, value) in additionalFields {
            try container.encode(value, forKey: DynamicCodingKey(key))
        }
    }
}

public enum ClaudeConfigStore {
    public static func load(from url: URL) throws -> ClaudeConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ClaudeConfig.self, from: data)
    }

    public static func loadIfPresent(from url: URL) throws -> ClaudeConfig? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try load(from: url)
    }

    public static func save(_ config: ClaudeConfig, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}