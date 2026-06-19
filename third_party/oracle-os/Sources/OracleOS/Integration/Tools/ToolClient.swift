import Foundation

public final class ToolClient: @unchecked Sendable {
    public init() {}

    public func health(_ manifest: ToolManifest) async -> Bool {
        guard let baseURL = URL(string: manifest.baseURL) else { return false }
        let url = baseURL.appendingPathComponent(manifest.healthPath)

        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200 ..< 300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    public func invoke(_ manifest: ToolManifest, envelope: ToolInvokeEnvelope) async throws -> ToolResponseEnvelope {
        guard let baseURL = URL(string: manifest.baseURL) else {
            throw NSError(
                domain: "ToolClient",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid base URL for tool \(manifest.id)"]
            )
        }

        let url = baseURL.appendingPathComponent(manifest.invokePath)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = TimeInterval(Double(manifest.timeouts.invokeMs) / 1000.0)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(envelope)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw NSError(
                domain: "ToolClient",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Tool \(manifest.id) returned non-2xx"]
            )
        }

        return try JSONDecoder().decode(ToolResponseEnvelope.self, from: data)
    }
}
