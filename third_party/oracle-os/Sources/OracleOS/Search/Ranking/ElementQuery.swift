import Foundation

public struct ElementQuery: Sendable {

    public let text: String?
    public let role: String?
    public let editable: Bool?
    public let clickable: Bool?
    public let visibleOnly: Bool
    public let app: String?

    public init(
        text: String? = nil,
        role: String? = nil,
        editable: Bool? = nil,
        clickable: Bool? = nil,
        visibleOnly: Bool = true,
        app: String? = nil
    ) {
        self.text = text
        self.role = role
        self.editable = editable
        self.clickable = clickable
        self.visibleOnly = visibleOnly
        self.app = app
    }
}
