import Foundation
public struct WindowModel: Sendable, Codable {
    public let id: String; public let title: String?; public let frame: CGRect
    public init(id: String, title: String?, frame: CGRect) {
        self.id = id; self.title = title; self.frame = frame
    }
}
