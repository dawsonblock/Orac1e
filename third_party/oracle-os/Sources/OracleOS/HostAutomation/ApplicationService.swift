import AppKit
import Foundation

@MainActor
public final class ApplicationService: ApplicationServicing {
    public init() {}

    public func runningApplications() -> [HostApplicationSnapshot] {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { !$0.isTerminated && $0.activationPolicy != .prohibited }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
            .map {
                HostApplicationSnapshot(
                    id: $0.bundleIdentifier ?? "\($0.processIdentifier)",
                    bundleIdentifier: $0.bundleIdentifier,
                    processIdentifier: $0.processIdentifier,
                    localizedName: $0.localizedName ?? "Unknown",
                    frontmost: $0.processIdentifier == frontmostPID
                )
            }
    }

    public func frontmostApplication() -> HostApplicationSnapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return HostApplicationSnapshot(
            id: app.bundleIdentifier ?? "\(app.processIdentifier)",
            bundleIdentifier: app.bundleIdentifier,
            processIdentifier: app.processIdentifier,
            localizedName: app.localizedName ?? "Unknown",
            frontmost: true
        )
    }

    @discardableResult
    public func activateApplication(named name: String) -> Bool {
        FocusManager.focus(appName: name).success
    }
}
