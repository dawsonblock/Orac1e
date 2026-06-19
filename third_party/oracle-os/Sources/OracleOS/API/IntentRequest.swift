// MARK: - Intent Core Types
// Oracle-OS vNext — Canonical intent value types.

import Foundation

// MARK: IntentDomain

public enum IntentDomain: String, Sendable, Codable, CaseIterable {
    case ui        = "ui"
    case code      = "code"
    case system    = "system"
    case mixed     = "mixed"
}

// MARK: IntentPriority

public enum IntentPriority: Int, Sendable, Codable, Comparable {
    case low      = 0
    case normal   = 1
    case high     = 2
    case critical = 3

    public static func < (lhs: IntentPriority, rhs: IntentPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: Intent

/// The sole input type for all runtime work.
/// Planners receive Intent and return Commands — they must never execute directly.
public struct Intent: Sendable, Codable {
    public let id: UUID
    public let domain: IntentDomain
    public let objective: String
    public let priority: IntentPriority
    public let metadata: [String: String]

    public init(
        id: UUID = UUID(),
        domain: IntentDomain,
        objective: String,
        priority: IntentPriority = .normal,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.domain = domain
        self.objective = objective
        self.priority = priority
        self.metadata = metadata
    }
}
