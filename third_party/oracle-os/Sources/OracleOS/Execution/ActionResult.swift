public struct ActionResult: Sendable, Codable {
    public let success: Bool
    public let verified: Bool
    public let message: String?
    public let method: String?
    public let verificationStatus: VerificationStatus?
    public let failureClass: String?
    public let elapsedMs: Double
    public let policyDecision: PolicyDecision?
    public let protectedOperation: String?
    public let approvalRequestID: String?
    public let approvalStatus: String?
    public let surface: String?
    public let appProtectionProfile: String?
    public let blockedByPolicy: Bool

    /// True when the action was executed through ``VerifiedExecutor``.
    /// Every action in the runtime loop must pass through the executor;
    /// consuming code can assert this flag to enforce the trust boundary.
    public let executedThroughExecutor: Bool

    public init(
        success: Bool,
        verified: Bool? = nil,
        message: String? = nil,
        method: String? = nil,
        verificationStatus: VerificationStatus? = nil,
        failureClass: String? = nil,
        elapsedMs: Double = 0,
        policyDecision: PolicyDecision? = nil,
        protectedOperation: String? = nil,
        approvalRequestID: String? = nil,
        approvalStatus: String? = nil,
        surface: String? = nil,
        appProtectionProfile: String? = nil,
        blockedByPolicy: Bool = false,
        executedThroughExecutor: Bool = false
    ) {
        self.success = success
        self.verified = verified ?? success
        self.message = message
        self.method = method
        self.verificationStatus = verificationStatus
        self.failureClass = failureClass
        self.elapsedMs = elapsedMs
        self.policyDecision = policyDecision
        self.protectedOperation = protectedOperation
        self.approvalRequestID = approvalRequestID
        self.approvalStatus = approvalStatus
        self.surface = surface
        self.appProtectionProfile = appProtectionProfile
        self.blockedByPolicy = blockedByPolicy
        self.executedThroughExecutor = executedThroughExecutor
    }

    public func toDict() -> [String: Any] {
        var result: [String: Any] = [
            "success": success,
            "verified": verified,
            "elapsed_ms": elapsedMs,
        ]

        if let message {
            result["message"] = message
        }
        if let method {
            result["method"] = method
        }
        if let verificationStatus {
            result["verification_status"] = verificationStatus.rawValue
        }
        if let failureClass {
            result["failure_class"] = failureClass
        }
        if let policyDecision {
            result["policy_decision"] = policyDecision.toDict()
        }
        if let protectedOperation {
            result["protected_operation"] = protectedOperation
        }
        if let approvalRequestID {
            result["approval_request_id"] = approvalRequestID
        }
        if let approvalStatus {
            result["approval_status"] = approvalStatus
        }
        if let surface {
            result["surface"] = surface
        }
        if let appProtectionProfile {
            result["app_protection_profile"] = appProtectionProfile
        }
        result["blocked_by_policy"] = blockedByPolicy
        result["executed_through_executor"] = executedThroughExecutor

        return result
    }

    public static func from(dict: [String: Any]) -> ActionResult? {
        guard let success = dict["success"] as? Bool else {
            return nil
        }

        let verificationStatus: VerificationStatus?
        if let raw = dict["verification_status"] as? String {
            verificationStatus = VerificationStatus(rawValue: raw)
        } else {
            verificationStatus = nil
        }

        return ActionResult(
            success: success,
            verified: dict["verified"] as? Bool ?? success,
            message: dict["message"] as? String,
            method: dict["method"] as? String,
            verificationStatus: verificationStatus,
            failureClass: dict["failure_class"] as? String,
            elapsedMs: dict["elapsed_ms"] as? Double ?? 0,
            policyDecision: nil,
            protectedOperation: dict["protected_operation"] as? String,
            approvalRequestID: dict["approval_request_id"] as? String,
            approvalStatus: dict["approval_status"] as? String,
            surface: dict["surface"] as? String,
            appProtectionProfile: dict["app_protection_profile"] as? String,
            blockedByPolicy: dict["blocked_by_policy"] as? Bool ?? false,
            executedThroughExecutor: dict["executed_through_executor"] as? Bool ?? false
        )
    }
}
