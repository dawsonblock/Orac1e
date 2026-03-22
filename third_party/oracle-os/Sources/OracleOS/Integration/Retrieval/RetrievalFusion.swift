import Foundation

public enum CodingRetrievalFusion {
    public static func topFiles(from results: [CodingRetrievalResult], limit: Int) -> [String] {
        Array(Set(results.prefix(limit).map(\.path))).sorted()
    }

    public static func topSnippets(from results: [CodingRetrievalResult], limit: Int) -> [CodingContextSnippet] {
        results.prefix(limit).map {
            CodingContextSnippet(
                path: $0.path,
                snippet: $0.snippet,
                startLine: $0.startLine,
                endLine: $0.endLine,
                score: $0.score
            )
        }
    }
}
