import Foundation

public enum RuntimeSurface: String, Codable, Sendable {
    case controller
    case mcp
    case cli
    case recipe
}
