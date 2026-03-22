import Foundation

public final class CodingRetrievalBrokerClient: @unchecked Sendable {
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func search(baseURL: URL, request: CodingRetrievalRequest) async throws -> CodingRetrievalResponse {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("search/code"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try decoder.decode(CodingRetrievalResponse.self, from: data)
    }
}
