import Foundation

public enum GovernanceRuleID: String, Codable, Sendable, CaseIterable {
    case executionTruthPath = "G1"
    case reusableKnowledge = "G2"
    case hierarchicalPlanning = "G3"
    case recoveryMode = "G4"
    case evalBeforeGrowth = "G5"

    public var title: String {
        switch self {
        case .executionTruthPath:
            "Execution Truth Path"
        case .reusableKnowledge:
            "Reusable Knowledge vs Episode Residue"
        case .hierarchicalPlanning:
            "Hierarchical Planning / Local Execution"
        case .recoveryMode:
            "Recovery as First-Class Execution Mode"
        case .evalBeforeGrowth:
            "Evaluation Before Architecture Growth"
        }
    }
}

public enum GovernanceSeverity: String, Codable, Sendable {
    case advisory
    case hardFail = "hard-fail"
}

public struct GovernanceViolation: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let ruleID: GovernanceRuleID
    public let severity: GovernanceSeverity
    public let title: String
    public let summary: String
    public let affectedModules: [String]
    public let evidence: [String]

    public init(
        id: String = UUID().uuidString,
        ruleID: GovernanceRuleID,
        severity: GovernanceSeverity,
        title: String,
        summary: String,
        affectedModules: [String] = [],
        evidence: [String] = []
    ) {
        self.id = id
        self.ruleID = ruleID
        self.severity = severity
        self.title = title
        self.summary = summary
        self.affectedModules = affectedModules
        self.evidence = evidence
    }
}

public struct GovernanceReport: Codable, Sendable, Equatable {
    public let violations: [GovernanceViolation]

    public init(violations: [GovernanceViolation] = []) {
        self.violations = violations
    }

    public static let empty = GovernanceReport()

    public var hardFailures: [GovernanceViolation] {
        violations.filter { $0.severity == .hardFail }
    }

    public var advisories: [GovernanceViolation] {
        violations.filter { $0.severity == .advisory }
    }

    public var isBlocking: Bool {
        !hardFailures.isEmpty
    }
}

extension GovernanceViolation {
    public func asArchitectureFinding() -> ArchitectureFinding {
        ArchitectureFinding(
            title: "[\(ruleID.rawValue)] \(title)",
            summary: summary,
            severity: severity == .hardFail ? .critical : .warning,
            affectedModules: affectedModules,
            evidence: evidence,
            riskScore: severity == .hardFail ? 0.95 : 0.7,
            governanceRuleID: ruleID,
            governanceSeverity: severity
        )
    }
}
