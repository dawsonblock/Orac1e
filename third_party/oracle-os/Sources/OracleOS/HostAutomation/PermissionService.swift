import ApplicationServices
import Foundation

@MainActor
public final class PermissionService {
    public init() {}

    public func snapshot() -> HostPermissionsSnapshot {
        HostPermissionsSnapshot(
            accessibilityGranted: AXIsProcessTrusted(),
            screenRecordingGranted: ScreenCapture.hasPermission()
        )
    }
}
