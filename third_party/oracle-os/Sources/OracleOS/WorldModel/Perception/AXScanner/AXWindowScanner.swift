import Foundation
#if canImport(AppKit)
import AppKit
/// Scans top-level windows for all running applications.
public struct AXWindowScanner {
    public init() {}
    public func scanVisibleWindows() -> [ScannedWindow] { [] }
}
public struct ScannedWindow: Sendable {
    public let appBundleID: String; public let pid: pid_t; public let title: String?; public let frame: CGRect
    public init(appBundleID: String, pid: pid_t, title: String?, frame: CGRect) {
        self.appBundleID = appBundleID; self.pid = pid; self.title = title; self.frame = frame }
}
#endif
