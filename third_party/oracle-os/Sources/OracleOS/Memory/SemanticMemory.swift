import Foundation
/// Stores distilled facts and embeddings.
public actor SemanticMemory {
    private var facts: [MemoryCandidate] = []
    public init() {}
    public func store(_ candidate: MemoryCandidate) { facts.append(candidate) }
    public func retrieve(query: String) -> [MemoryCandidate] { facts }
}
