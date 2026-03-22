import Foundation

@MainActor
public protocol WindowServicing {
    func focusedWindow(appName: String?) -> HostWindowSnapshot?
    func visibleWindows(appName: String?) -> [HostWindowSnapshot]
}
