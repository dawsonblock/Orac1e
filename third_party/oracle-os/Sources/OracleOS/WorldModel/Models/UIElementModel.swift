import Foundation
public struct UIElementModel: Sendable, Codable {
    public let stableID: String; public let role: String; public let title: String?
    public let frame: CGRect?; public let actions: [String]
    public init(stableID: String, role: String, title: String?, frame: CGRect?, actions: [String]) {
        self.stableID = stableID; self.role = role; self.title = title; self.frame = frame; self.actions = actions
    }
}
