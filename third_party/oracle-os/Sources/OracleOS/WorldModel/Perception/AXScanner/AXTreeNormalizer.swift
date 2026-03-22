import Foundation
/// Normalizes a raw AX tree into a stable, serializable form.
public struct AXTreeNormalizer {
    public init() {}
    public func normalize(_ nodes: [RawPerceivedNode]) -> [NormalizedAXNode] {
        nodes.map { NormalizedAXNode(stableID: $0.stableID, role: $0.role, title: $0.title,
                                     frame: $0.frame, isVisible: true, isEnabled: true, actions: []) }
    }
}
public struct RawPerceivedNode: Sendable {
    public let stableID: String; public let role: String; public let title: String?; public let frame: CGRect?
    public init(stableID: String, role: String, title: String?, frame: CGRect?) {
        self.stableID = stableID; self.role = role; self.title = title; self.frame = frame }
}
public struct NormalizedAXNode: Sendable {
    public let stableID: String; public let role: String; public let title: String?
    public let frame: CGRect?; public let isVisible: Bool; public let isEnabled: Bool; public let actions: [String]
    public init(stableID: String, role: String, title: String?, frame: CGRect?,
                isVisible: Bool, isEnabled: Bool, actions: [String]) {
        self.stableID = stableID; self.role = role; self.title = title; self.frame = frame
        self.isVisible = isVisible; self.isEnabled = isEnabled; self.actions = actions }
}
