import Foundation

/// Persistent trace storage using JSONL format.
///
/// Traces store verified execution deltas, not bloated snapshots.
/// Large raw observations are written only when debug mode is active.
public final class ExperienceStore: @unchecked Sendable {
    public let directoryURL: URL

    private let encoder: JSONEncoder
    private let writeLock = NSLock()

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601

        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    public convenience init() {
        self.init(directoryURL: Self.resolveSessionsDirectory())
    }

    @discardableResult
    public func append(_ event: TraceEvent) throws -> URL {
        writeLock.lock()
        defer { writeLock.unlock() }

        let fileURL = directoryURL.appendingPathComponent("\(event.sessionID).jsonl")
        let data = try encoder.encode(event)
        var line = data
        line.append(0x0A)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
        }

        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        return fileURL
    }

    public static func traceRootDirectory() -> URL {
        OracleProductPaths.tracesRootDirectory
    }

    public static func resolveSessionsDirectory() -> URL {
        traceRootDirectory().appendingPathComponent("sessions", isDirectory: true)
    }
}
