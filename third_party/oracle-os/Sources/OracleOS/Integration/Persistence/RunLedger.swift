import Foundation

public actor CodingRunLedger {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(baseURL: URL) {
        fileURL = baseURL.appendingPathComponent("runs.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func all() throws -> [CodingRunRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        return try decoder.decode([CodingRunRecord].self, from: Data(contentsOf: fileURL))
    }

    public func upsert(_ record: CodingRunRecord) throws {
        var items = try all().filter { $0.id != record.id }
        items.append(record)
        let data = try encoder.encode(items.sorted { $0.createdAt < $1.createdAt })
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try data.write(to: fileURL)
    }
}
