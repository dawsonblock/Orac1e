import Foundation

public struct CapabilityPolicy: Sendable {
    public let allowedCapabilities: Set<String>
    public let riskLevel: RiskLevel?
    
    public init(allowedCapabilities: Set<String> = [], riskLevel: RiskLevel? = nil) {
        self.allowedCapabilities = allowedCapabilities
        self.riskLevel = riskLevel
    }
    
    /// Check if a capability is allowed
    public func canExecute(capability: String) -> Bool {
        // If no restrictions, allow all
        if allowedCapabilities.isEmpty {
            return true
        }
        return allowedCapabilities.contains(capability)
    }
    
    /// Check if an action intent is allowed based on policy
    public func canExecute(intent: ActionIntent) -> Bool {
        // Use the existing PolicyEngine for evaluation
        let decision = PolicyEngine.shared.evaluate(intent: intent)
        return decision.allowed
    }
    
    /// Filter a list of capabilities to only allowed ones
    public func filter(capabilities: [String]) -> [String] {
        if allowedCapabilities.isEmpty {
            return capabilities
        }
        return capabilities.filter { allowedCapabilities.contains($0) }
    }
    
    /// Create from ToolPolicyConfig
    public static func from(config: ToolPolicyConfig, for capability: String? = nil) -> CapabilityPolicy {
        // Get capability-specific override or use default
        let policy = config.capabilityOverrides[capability ?? ""] ?? config.defaultPolicy
        
        var allowed = Set<String>()
        
        if policy.allowLow {
            allowed.insert("low")
        }
        if policy.allowRisky {
            allowed.insert("risky")
        }
        if policy.allowBlocked {
            allowed.insert("blocked")
        }
        
        // Determine overall risk level based on what's allowed
        var riskLevel: RiskLevel? = nil
        if !policy.allowBlocked {
            riskLevel = .blocked
        } else if !policy.allowRisky {
            riskLevel = .risky
        } else if !policy.allowLow {
            riskLevel = .low
        }
        
        return CapabilityPolicy(allowedCapabilities: allowed, riskLevel: riskLevel)
    }
    
    /// Default policy - allows all capabilities
    public static let `default` = CapabilityPolicy()
    
    /// Restrictive policy - only allows low risk
    public static let restrictive = CapabilityPolicy(
        allowedCapabilities: ["low"],
        riskLevel: .low
    )
}
