import Foundation
import CoreGraphics

public struct HostApplicationSnapshot: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let bundleIdentifier: String?
    public let processIdentifier: Int32
    public let localizedName: String
    public let frontmost: Bool

    public init(
        id: String,
        bundleIdentifier: String?,
        processIdentifier: Int32,
        localizedName: String,
        frontmost: Bool
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.localizedName = localizedName
        self.frontmost = frontmost
    }
}

public struct HostWindowSnapshot: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let appName: String
    public let title: String?
    public let frame: CGRect?
    public let focused: Bool
    public let elementCount: Int

    public init(
        id: String,
        appName: String,
        title: String?,
        frame: CGRect?,
        focused: Bool,
        elementCount: Int
    ) {
        self.id = id
        self.appName = appName
        self.title = title
        self.frame = frame
        self.focused = focused
        self.elementCount = elementCount
    }
}

public struct HostMenuItemSnapshot: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let path: String

    public init(id: String, title: String, path: String) {
        self.id = id
        self.title = title
        self.path = path
    }
}

public struct HostDialogSnapshot: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String?
    public let message: String?
    public let buttonLabels: [String]

    public init(id: String, title: String?, message: String?, buttonLabels: [String]) {
        self.id = id
        self.title = title
        self.message = message
        self.buttonLabels = buttonLabels
    }
}

public struct HostCaptureSnapshot: Codable, Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let windowTitle: String?
    public let capturedAt: Date

    public init(width: Int, height: Int, windowTitle: String?, capturedAt: Date = Date()) {
        self.width = width
        self.height = height
        self.windowTitle = windowTitle
        self.capturedAt = capturedAt
    }
}

public struct HostPermissionsSnapshot: Codable, Sendable, Equatable {
    public let accessibilityGranted: Bool
    public let screenRecordingGranted: Bool

    public init(accessibilityGranted: Bool, screenRecordingGranted: Bool) {
        self.accessibilityGranted = accessibilityGranted
        self.screenRecordingGranted = screenRecordingGranted
    }
}

public struct HostSnapshot: Codable, Sendable, Equatable {
    public let capturedAt: Date
    public let activeApplication: HostApplicationSnapshot?
    public let windows: [HostWindowSnapshot]
    public let menus: [HostMenuItemSnapshot]
    public let dialog: HostDialogSnapshot?
    public let capture: HostCaptureSnapshot?
    public let permissions: HostPermissionsSnapshot
    public let snapshotID: String

    public init(
        capturedAt: Date = Date(),
        activeApplication: HostApplicationSnapshot?,
        windows: [HostWindowSnapshot],
        menus: [HostMenuItemSnapshot],
        dialog: HostDialogSnapshot?,
        capture: HostCaptureSnapshot?,
        permissions: HostPermissionsSnapshot,
        snapshotID: String
    ) {
        self.capturedAt = capturedAt
        self.activeApplication = activeApplication
        self.windows = windows
        self.menus = menus
        self.dialog = dialog
        self.capture = capture
        self.permissions = permissions
        self.snapshotID = snapshotID
    }
}
