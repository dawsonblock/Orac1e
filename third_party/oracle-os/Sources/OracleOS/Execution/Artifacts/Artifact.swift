import Foundation
public protocol Artifact: Sendable {}
public struct FileArtifact: Artifact, Sendable, Codable {
    public let path: String; public let content: String
    public init(path: String, content: String) { self.path = path; self.content = content }
}
public struct BuildArtifact: Artifact, Sendable, Codable {
    public let status: String; public let output: String
    public init(status: String, output: String) { self.status = status; self.output = output }
}
public struct ScreenshotArtifact: Artifact, Sendable, Codable {
    public let pngData: Data; public let timestamp: Date
    public init(pngData: Data, timestamp: Date = Date()) { self.pngData = pngData; self.timestamp = timestamp }
}
