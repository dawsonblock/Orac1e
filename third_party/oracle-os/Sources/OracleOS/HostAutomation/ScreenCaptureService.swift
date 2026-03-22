import AppKit
import Foundation

@MainActor
public final class ScreenCaptureService: CaptureServicing {
    private let processService: ProcessService

    public init(processService: ProcessService = ProcessService()) {
        self.processService = processService
    }

    public func captureFrontmost(appName: String?) -> HostCaptureSnapshot? {
        let targetPID: Int32?
        if let appName {
            targetPID = processService.processIdentifier(forAppNamed: appName)
        } else {
            targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        }

        guard let pid = targetPID,
              let result = ScreenCapture.captureWindowSync(pid: pid)
        else {
            return nil
        }

        return HostCaptureSnapshot(
            width: result.width,
            height: result.height,
            windowTitle: result.windowTitle
        )
    }
}
