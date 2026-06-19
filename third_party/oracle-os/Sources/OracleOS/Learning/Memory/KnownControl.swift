import Foundation

public struct KnownControl: Codable {

    public let key: String
    public let app: String
    public let label: String?
    public let role: String?
    public let elementID: String?
    public let successCount: Int
    public let lastUsed: Date

    public init(
        key: String,
        app: String,
        label: String?,
        role: String?,
        elementID: String?,
        successCount: Int,
        lastUsed: Date = Date()
    ) {
        self.key = key
        self.app = app
        self.label = label
        self.role = role
        self.elementID = elementID
        self.successCount = successCount
        self.lastUsed = lastUsed
    }
}
