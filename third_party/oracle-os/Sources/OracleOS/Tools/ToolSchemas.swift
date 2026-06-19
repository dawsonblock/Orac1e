import Foundation

public struct ToolSchema: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let description: String
    public let requiredArguments: [String]

    public init(id: String, description: String, requiredArguments: [String]) {
        self.id = id
        self.description = description
        self.requiredArguments = requiredArguments
    }
}

public enum ToolSchemas {
    public static func schema(for command: ToolCommandSpec) -> ToolSchema {
        switch (command.family, command.name) {
        case (.app, "launch"):
            return ToolSchema(id: command.id, description: "Launch or focus an application", requiredArguments: ["app"])
        case (.window, "focus"):
            return ToolSchema(id: command.id, description: "Focus a specific window", requiredArguments: ["app"])
        case (.click, "semantic_click"):
            return ToolSchema(id: command.id, description: "Click a semantically resolved target", requiredArguments: ["query"])
        case (.type, "semantic_type"):
            return ToolSchema(id: command.id, description: "Type into a semantically resolved field", requiredArguments: ["query", "text"])
        case (.capture, "snapshot"):
            return ToolSchema(id: command.id, description: "Capture a structured host snapshot", requiredArguments: [])
        default:
            return ToolSchema(id: command.id, description: "Oracle OS tool command", requiredArguments: [])
        }
    }
}
