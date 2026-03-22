import Foundation

public final class CodingWorkerClient: @unchecked Sendable {
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func propose(baseURL: URL, request: CodingWorkerProposeRequest) async throws -> CodingWorkerProposeResponse {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("propose"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try decoder.decode(CodingWorkerProposeResponse.self, from: data)
    }
}
