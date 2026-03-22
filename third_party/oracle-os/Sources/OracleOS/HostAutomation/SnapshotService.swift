import Foundation

@MainActor
public final class SnapshotService {
    private let applications: any ApplicationServicing
    private let windows: any WindowServicing
    private let menus: any MenuServicing
    private let dialogs: any DialogServicing
    private let capture: any CaptureServicing
    private let permissions: PermissionService

    public init(
        applications: any ApplicationServicing,
        windows: any WindowServicing,
        menus: any MenuServicing,
        dialogs: any DialogServicing,
        capture: any CaptureServicing,
        permissions: PermissionService
    ) {
        self.applications = applications
        self.windows = windows
        self.menus = menus
        self.dialogs = dialogs
        self.capture = capture
        self.permissions = permissions
    }

    public func captureSnapshot(appName: String? = nil) -> HostSnapshot {
        let activeApplication = appName.flatMap { name in
            applications.runningApplications().first(where: { $0.localizedName == name })
        } ?? applications.frontmostApplication()
        let targetAppName = appName ?? activeApplication?.localizedName
        let windows = windows.visibleWindows(appName: targetAppName)
        let dialog = dialogs.activeDialog(appName: targetAppName)
        let capture = capture.captureFrontmost(appName: targetAppName)
        let permissions = permissions.snapshot()
        let snapshotID = [
            activeApplication?.localizedName ?? "unknown",
            windows.first?.title ?? "window",
            dialog?.title ?? "no-dialog",
        ].joined(separator: "|")

        return HostSnapshot(
            activeApplication: activeApplication,
            windows: windows,
            menus: menus.menuItems(appName: targetAppName),
            dialog: dialog,
            capture: capture,
            permissions: permissions,
            snapshotID: snapshotID
        )
    }
}
