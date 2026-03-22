import Foundation

public enum ApprovalStatus: String, Codable, Sendable {
    case pending
    case approved
    case rejected
    case executed
    case expired
}

public struct ApprovalRequest: Codable, Sendable, Identifiable {
    public let id: String
    public let createdAt: Date
    public let surface: RuntimeSurface
    public let toolName: String?
    public let appName: String?
    public let displayTitle: String
    public let reason: String
    public let riskLevel: RiskLevel
    public let protectedOperation: ProtectedOperation
    public let actionFingerprint: String
    public let appProtectionProfile: AppProtectionProfile
    public let status: ApprovalStatus

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        surface: RuntimeSurface,
        toolName: String?,
        appName: String?,
        displayTitle: String,
        reason: String,
        riskLevel: RiskLevel,
        protectedOperation: ProtectedOperation,
        actionFingerprint: String,
        appProtectionProfile: AppProtectionProfile,
        status: ApprovalStatus = .pending
    ) {
        self.id = id
        self.createdAt = createdAt
        self.surface = surface
        self.toolName = toolName
        self.appName = appName
        self.displayTitle = displayTitle
        self.reason = reason
        self.riskLevel = riskLevel
        self.protectedOperation = protectedOperation
        self.actionFingerprint = actionFingerprint
        self.appProtectionProfile = appProtectionProfile
        self.status = status
    }
}
