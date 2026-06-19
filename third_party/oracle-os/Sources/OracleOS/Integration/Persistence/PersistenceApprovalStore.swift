import Foundation

public actor CodingApprovalStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()

    public init(baseURL: URL) {
        fileURL = baseURL.appendingPathComponent("approvals.jsonl")
        encoder.dateEncodingStrategy = .iso8601
    }

    public func append(_ decision: CodingApprovalDecision) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        let data = try encoder.encode(decision) + Data("\n".utf8)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: fileURL)
        }
    }
}
