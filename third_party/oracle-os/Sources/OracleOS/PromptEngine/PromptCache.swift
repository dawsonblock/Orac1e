import CryptoKit
import Foundation

public final class PromptCache: @unchecked Sendable {
    public static let shared = PromptCache()

    private let lock = NSLock()
    private var storage: [String: PromptDocument] = [:]

    public init() {}

    public func document(for key: String) -> PromptDocument? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    public func store(_ document: PromptDocument, for key: String) {
        lock.lock()
        storage[key] = document
        lock.unlock()
    }

    public static func cacheKey(for context: PromptContext) -> String {
        let payload = [
            context.templateKind.rawValue,
            context.goal,
            context.context.joined(separator: "\n"),
            context.state.joined(separator: "\n"),
            context.constraints.joined(separator: "\n"),
            context.availableActions.joined(separator: "\n"),
            context.relevantKnowledge.joined(separator: "\n"),
            context.expectedOutput.joined(separator: "\n"),
            context.evaluationCriteria.joined(separator: "\n"),
        ].joined(separator: "\n---\n")

        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
