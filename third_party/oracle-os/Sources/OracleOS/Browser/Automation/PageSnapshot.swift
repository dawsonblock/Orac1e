import Foundation
import CoreGraphics

public struct PageIndexedElement: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let index: Int
    public let role: String?
    public let label: String?
    public let value: String?
    public let domID: String?
    public let tag: String?
    public let className: String?
    public let frame: CGRect?
    public let focused: Bool
    public let enabled: Bool
    public let visible: Bool

    public init(
        id: String,
        index: Int,
        role: String?,
        label: String?,
        value: String?,
        domID: String?,
        tag: String?,
        className: String?,
        frame: CGRect?,
        focused: Bool,
        enabled: Bool,
        visible: Bool
    ) {
        self.id = id
        self.index = index
        self.role = role
        self.label = label
        self.value = value
        self.domID = domID
        self.tag = tag
        self.className = className
        self.frame = frame
        self.focused = focused
        self.enabled = enabled
        self.visible = visible
    }
}

public struct PageSnapshot: Codable, Sendable, Equatable {
    public let browserApp: String
    public let title: String?
    public let url: String?
    public let domain: String?
    public let simplifiedText: String
    public let indexedElements: [PageIndexedElement]
    public let capturedAt: Date

    public init(
        browserApp: String,
        title: String?,
        url: String?,
        domain: String?,
        simplifiedText: String,
        indexedElements: [PageIndexedElement],
        capturedAt: Date = Date()
    ) {
        self.browserApp = browserApp
        self.title = title
        self.url = url
        self.domain = domain
        self.simplifiedText = simplifiedText
        self.indexedElements = indexedElements
        self.capturedAt = capturedAt
    }
}
