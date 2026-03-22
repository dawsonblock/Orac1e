import Foundation

/// Risk level classification for actions
public enum RiskLevel: String, Codable, Sendable, CaseIterable {
    case low
    case medium
    case high
    
    /// Determine risk level from action type
    public static func from(action: String, category: String?, mutatesWorkspace: Bool = false, touchesNetwork: Bool = false) -> RiskLevel {
        // High risk: destructive operations, network access, git pushes
        let highRiskActions = ["git-push", "git-commit", "delete", "remove", "drop"]
        if highRiskActions.contains(action.lowercased()) {
            return .high
        }
        
        // Network access is high risk
        if touchesNetwork {
            return .high
        }
        
        // Medium risk: write operations, build, test
        let mediumRiskActions = ["edit-file", "write-file", "generate-patch", "build", "test", "git-branch"]
        if mediumRiskActions.contains(action.lowercased()) || mutatesWorkspace {
            return .medium
        }
        
        // Low risk: read-only operations
        return .low
    }
    
    /// Determine risk from CodeCommandCategory
    public static func from(category: CodeCommandCategory?) -> RiskLevel {
        guard let category = category else { return .low }
        
        switch category {
        case .gitPush:
            return .high
        case .gitCommit, .gitBranch:
            return .medium
        case .editFile, .writeFile, .generatePatch:
            return .medium
        case .build, .test:
            return .medium
        case .indexRepository, .searchCode, .openFile:
            return .low
        case .formatter, .linter, .gitStatus:
            return .low
        case .parseBuildFailure, .parseTestFailure:
            return .low
        }
    }
}

/// Policy configuration loaded from JSON
public struct ApprovalPolicyConfig: Codable, Sendable {
    public let requireApplyApproval: Bool
    public let allowAutoApproveInTestMode: Bool
    
    public init(requireApplyApproval: Bool = true, allowAutoApproveInTestMode: Bool = true) {
        self.requireApplyApproval = requireApplyApproval
        self.allowAutoApproveInTestMode = allowAutoApproveInTestMode
    }
}

/// Tool policy configuration loaded from JSON
public struct ToolPolicyConfig: Codable, Sendable {
    public let defaultPolicy: RiskPolicy
    public let capabilityOverrides: [String: RiskPolicy]
    
    public struct RiskPolicy: Codable, Sendable {
        public let allowLow: Bool
        public let allowMedium: Bool
        public let allowHigh: Bool
        
        public init(allowLow: Bool = true, allowMedium: Bool = true, allowHigh: Bool = false) {
            self.allowLow = allowLow
            self.allowMedium = allowMedium
            self.allowHigh = allowHigh
        }
        
        public func canExecute(risk: RiskLevel) -> Bool {
            switch risk {
            case .low: return allowLow
            case .medium: return allowMedium
            case .high: return allowHigh
            }
        }
    }
    
    public init(defaultPolicy: RiskPolicy = RiskPolicy(), capabilityOverrides: [String: RiskPolicy] = [:]) {
        self.defaultPolicy = defaultPolicy
        self.capabilityOverrides = capabilityOverrides
    }
}