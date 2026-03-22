import Foundation
public struct ApplicationModel: Sendable, Codable {
    public let bundleID: String; public let name: String; public let pid: Int32
    public init(bundleID: String, name: String, pid: Int32) {
        self.bundleID = bundleID; self.name = name; self.pid = pid
    }
}
