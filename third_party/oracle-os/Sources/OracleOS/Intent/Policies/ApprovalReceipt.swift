import Foundation

public struct ApprovalReceipt: Codable, Sendable {
    public let requestID: String
    public let approvedAt: Date
    public let actionFingerprint: String
    public let approvedBy: String
    public let consumed: Bool

    public init(
        requestID: String,
        approvedAt: Date = Date(),
        actionFingerprint: String,
        approvedBy: String = "controller",
        consumed: Bool = false
    ) {
        self.requestID = requestID
        self.approvedAt = approvedAt
        self.actionFingerprint = actionFingerprint
        self.approvedBy = approvedBy
        self.consumed = consumed
    }
}
