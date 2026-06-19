import Foundation
#if canImport(AppKit)
import AppKit

/// Scans raw AX nodes from a running application.
public struct AXNodeScanner {
    public init() {}
    public func scan(pid: pid_t) throws -> [RawAXNode] { [] }
}
public struct RawAXNode: @unchecked Sendable {
    public let ref: AnyObject
    public let role: String
    public let title: String?
    public let frame: CGRect?
    public init(ref: AnyObject, role: String, title: String?, frame: CGRect?) {
        self.ref = ref; self.role = role; self.title = title; self.frame = frame }
}
#endif
