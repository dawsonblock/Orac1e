import Foundation

public struct ActionApproval: Sendable {
    public let approved: Bool
    public let conditions: [String]
    public let riskLevel: RiskLevel?
    public let timestamp: Date
    
    public init(approved: Bool, conditions: [String] = [], riskLevel: RiskLevel? = nil) {
        self.approved = approved
        self.conditions = conditions
        self.riskLevel = riskLevel
        self.timestamp = Date()
    }
    
    /// Evaluate an action using the existing PolicyEngine
    public static func evaluate(
        intent: ActionIntent,
        isTestMode: Bool = false
    ) -> ActionApproval {
        // Use the existing PolicyEngine for evaluation
        let decision = PolicyEngine.shared.evaluate(intent: intent)
        
        // In test mode with open policy, auto-approve low-risk actions
        if isTestMode && PolicyEngine.shared.mode == .open && decision.riskLevel == .low {
            return ActionApproval(
                approved: true,
                conditions: ["auto-approved in test mode"],
                riskLevel: decision.riskLevel
            )
        }
        
        return ActionApproval(
            approved: decision.allowed,
            conditions: decision.reason.map { [$0] } ?? [],
            riskLevel: decision.riskLevel
        )
    }
    
    /// Create from PolicyDecision
    public static func from(decision: PolicyDecision) -> ActionApproval {
        return ActionApproval(
            approved: decision.allowed,
            conditions: decision.reason.map { [$0] } ?? [],
            riskLevel: decision.riskLevel
        )
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
    
    /// Load from JSON file
    public static func load(from path: String) throws -> ApprovalPolicyConfig {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ApprovalPolicyConfig.self, from: data)
    }
    
    /// Default configuration
    public static let `default` = ApprovalPolicyConfig()
}

/// Tool policy configuration loaded from JSON
public struct ToolPolicyConfig: Codable, Sendable {
    public let defaultPolicy: RiskPolicy
    public let capabilityOverrides: [String: RiskPolicy]
    
    public struct RiskPolicy: Codable, Sendable {
        public let allowLow: Bool
        public let allowRisky: Bool
        public let allowBlocked: Bool
        
        public init(allowLow: Bool = true, allowRisky: Bool = true, allowBlocked: Bool = false) {
            self.allowLow = allowLow
            self.allowRisky = allowRisky
            self.allowBlocked = allowBlocked
        }
        
        public func canExecute(risk: RiskLevel) -> Bool {
            switch risk {
            case .low: return allowLow
            case .risky: return allowRisky
            case .blocked: return allowBlocked
            }
        }
    }
    
    public init(defaultPolicy: RiskPolicy = RiskPolicy(), capabilityOverrides: [String: RiskPolicy] = [:]) {
        self.defaultPolicy = defaultPolicy
        self.capabilityOverrides = capabilityOverrides
    }
    
    /// Load from JSON file
    public static func load(from path: String) throws -> ToolPolicyConfig {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ToolPolicyConfig.self, from: data)
    }
    
    /// Default configuration
    public static let `default` = ToolPolicyConfig()
}
