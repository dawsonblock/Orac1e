import Foundation

public struct FailurePattern: Codable {

    public let app: String
    public let failure: FailureClass
    public let action: String
    public let timestamp: Date

    public init(
        app: String,
        failure: FailureClass,
        action: String
    ) {
        self.app = app
        self.failure = failure
        self.action = action
        self.timestamp = Date()
    }
}
