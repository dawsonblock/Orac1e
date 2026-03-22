import Foundation

public struct BrowserSession: Codable, Sendable, Equatable {
    public let appName: String
    public let page: PageSnapshot?
    public let available: Bool

    public init(appName: String, page: PageSnapshot?, available: Bool) {
        self.appName = appName
        self.page = page
        self.available = available
    }
}
