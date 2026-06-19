import Foundation

public enum RiskLevel: String, Codable, Sendable {
    case low
    case risky
    case blocked
}

public enum PolicyMode: String, Codable, Sendable {
    case open
    case confirmRisky = "confirm-risky"
    case lockedDown = "locked-down"
}
