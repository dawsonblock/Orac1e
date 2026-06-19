import Foundation
public struct CodeQuery: Sendable {
    public let text: String; public let fileTypes: [String]; public let maxResults: Int
    public init(text: String, fileTypes: [String] = [], maxResults: Int = 20) {
        self.text = text; self.fileTypes = fileTypes; self.maxResults = maxResults
    }
}
