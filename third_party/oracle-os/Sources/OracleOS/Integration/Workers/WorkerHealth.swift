import Foundation

public struct CodingWorkerHealth: Codable, Sendable {
    public let name: String
    public let ok: Bool
    public let details: [String: String]?
}

public final class CodingWorkerHealthClient: @unchecked Sendable {
    private let session: URLSession
    private let decoder = JSONDecoder()

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func health(baseURL: URL) async throws -> CodingWorkerHealth {
        let (data, response) = try await session.data(from: baseURL.appendingPathComponent("health"))
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try decoder.decode(CodingWorkerHealth.self, from: data)
    }
}
