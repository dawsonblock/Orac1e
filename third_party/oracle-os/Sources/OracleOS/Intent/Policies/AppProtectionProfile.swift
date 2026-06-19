import Foundation

public enum AppProtectionProfile: String, Codable, Sendable {
    case blocked
    case confirmRisky = "confirm-risky"
    case lowRiskAllowed = "low-risk-allowed"
}
