import Foundation

@MainActor
public struct AutomationHost {
    public let applications: any ApplicationServicing
    public let windows: any WindowServicing
    public let menus: any MenuServicing
    public let dialogs: any DialogServicing
    public let processes: ProcessService
    public let screenCapture: any CaptureServicing
    public let snapshots: SnapshotService
    public let permissions: PermissionService

    public init(
        applications: any ApplicationServicing,
        windows: any WindowServicing,
        menus: any MenuServicing,
        dialogs: any DialogServicing,
        processes: ProcessService,
        screenCapture: any CaptureServicing,
        snapshots: SnapshotService,
        permissions: PermissionService
    ) {
        self.applications = applications
        self.windows = windows
        self.menus = menus
        self.dialogs = dialogs
        self.processes = processes
        self.screenCapture = screenCapture
        self.snapshots = snapshots
        self.permissions = permissions
    }

    public static func live() -> AutomationHost {
        let applications = ApplicationService()
        let windows = WindowService()
        let menus = MenuService()
        let dialogs = DialogService()
        let processes = ProcessService()
        let capture = ScreenCaptureService(processService: processes)
        let permissions = PermissionService()
        let snapshots = SnapshotService(
            applications: applications,
            windows: windows,
            menus: menus,
            dialogs: dialogs,
            capture: capture,
            permissions: permissions
        )
        return AutomationHost(
            applications: applications,
            windows: windows,
            menus: menus,
            dialogs: dialogs,
            processes: processes,
            screenCapture: capture,
            snapshots: snapshots,
            permissions: permissions
        )
    }
}
