import Foundation

public enum KnowledgeTier: String, Codable, Sendable, CaseIterable {
    case exploration
    case candidate
    case stable
    case experiment
    case recovery
}
