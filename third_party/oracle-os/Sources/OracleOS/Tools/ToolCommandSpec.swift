import Foundation

public enum ToolCommandFamily: String, Codable, Sendable, CaseIterable {
    case app
    case window
    case menu
    case dialog
    case click
    case type
    case hotkey
    case capture
    case shell
    case workflow
    case graphInspect = "graph_inspect"
    case memoryInspect = "memory_inspect"

    public var mutatesWorld: Bool {
        switch self {
        case .capture, .graphInspect, .memoryInspect:
            return false
        default:
            return true
        }
    }
}

public struct ToolCommandSpec: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let family: ToolCommandFamily
    public let name: String
    public let arguments: [String: String]

    public init(
        id: String? = nil,
        family: ToolCommandFamily,
        name: String,
        arguments: [String: String] = [:]
    ) {
        self.id = id ?? "\(family.rawValue):\(name)"
        self.family = family
        self.name = name
        self.arguments = arguments
    }
}
