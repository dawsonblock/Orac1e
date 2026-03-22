import Foundation

public struct StrategyRecord: Codable {

    public let app: String
    public let strategy: String
    public let success: Bool
    public let timestamp: Date

    public init(
        app: String,
        strategy: String,
        success: Bool
    ) {
        self.app = app
        self.strategy = strategy
        self.success = success
        self.timestamp = Date()
    }
}
