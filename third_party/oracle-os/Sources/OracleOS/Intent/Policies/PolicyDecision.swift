import Foundation

public struct PolicyDecision: Codable, Sendable {
    public let allowed: Bool
    public let riskLevel: RiskLevel
    public let requiresApproval: Bool
    public let protectedOperation: ProtectedOperation?
    public let approvalRequestID: String?
    public let appProtectionProfile: AppProtectionProfile
    public let blockedByPolicy: Bool
    public let surface: RuntimeSurface
    public let policyMode: PolicyMode
    public let reason: String?

    public init(
        allowed: Bool,
        riskLevel: RiskLevel,
        protectedOperation: ProtectedOperation? = nil,
        approvalRequestID: String? = nil,
        appProtectionProfile: AppProtectionProfile = .lowRiskAllowed,
        blockedByPolicy: Bool = false,
        surface: RuntimeSurface = .mcp,
        policyMode: PolicyMode = .confirmRisky,
        requiresApproval: Bool = false,
        reason: String? = nil
    ) {
        self.allowed = allowed
        self.riskLevel = riskLevel
        self.protectedOperation = protectedOperation
        self.approvalRequestID = approvalRequestID
        self.appProtectionProfile = appProtectionProfile
        self.blockedByPolicy = blockedByPolicy
        self.surface = surface
        self.policyMode = policyMode
        self.requiresApproval = requiresApproval
        self.reason = reason
    }

    public func toDict() -> [String: Any] {
        var result: [String: Any] = [
            "allowed": allowed,
            "risk_level": riskLevel.rawValue,
            "requires_approval": requiresApproval,
            "app_protection_profile": appProtectionProfile.rawValue,
            "blocked_by_policy": blockedByPolicy,
            "surface": surface.rawValue,
            "policy_mode": policyMode.rawValue,
        ]
        if let protectedOperation {
            result["protected_operation"] = protectedOperation.rawValue
        }
        if let approvalRequestID {
            result["approval_request_id"] = approvalRequestID
        }
        if let reason {
            result["reason"] = reason
        }
        return result
    }

    public func withApprovalRequest(id: String) -> PolicyDecision {
        PolicyDecision(
            allowed: false,
            riskLevel: riskLevel,
            protectedOperation: protectedOperation,
            approvalRequestID: id,
            appProtectionProfile: appProtectionProfile,
            blockedByPolicy: blockedByPolicy,
            surface: surface,
            policyMode: policyMode,
            requiresApproval: true,
            reason: reason
        )
    }

    public func withReason(_ reason: String) -> PolicyDecision {
        PolicyDecision(
            allowed: false,
            riskLevel: riskLevel,
            protectedOperation: protectedOperation,
            approvalRequestID: approvalRequestID,
            appProtectionProfile: appProtectionProfile,
            blockedByPolicy: true,
            surface: surface,
            policyMode: policyMode,
            requiresApproval: requiresApproval,
            reason: reason
        )
    }
}
