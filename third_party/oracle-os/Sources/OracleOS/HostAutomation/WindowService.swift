import AppKit
import Foundation

@MainActor
public final class WindowService: WindowServicing {
    public init() {}

    public func focusedWindow(appName: String?) -> HostWindowSnapshot? {
        visibleWindows(appName: appName).first(where: \.focused)
    }

    public func visibleWindows(appName: String?) -> [HostWindowSnapshot] {
        let observation = ObservationBuilder.capture(appName: appName, maxDepth: 8, maxElements: 80)
        let resolvedAppName = observation.app ?? appName ?? "Unknown"
        let frame = observation.elements.first(where: \.focused)?.frame
        let window = HostWindowSnapshot(
            id: [resolvedAppName, observation.windowTitle ?? "window"].joined(separator: "|"),
            appName: resolvedAppName,
            title: observation.windowTitle,
            frame: frame,
            focused: true,
            elementCount: observation.elements.count
        )
        return [window]
    }
}
