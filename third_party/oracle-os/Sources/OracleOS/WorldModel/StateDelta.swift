import Foundation

public struct StateDelta: Sendable {
    public let previousStateHash: String
    public let currentStateHash: String
    public let changedElements: [String]
    
    public init(previousStateHash: String, currentStateHash: String, changedElements: [String] = []) {
        self.previousStateHash = previousStateHash
        self.currentStateHash = currentStateHash
        self.changedElements = changedElements
    }
}
