import Foundation
/// Repository-specific artifact and task history.
public actor ProjectMemory {
    private var history: [String: [MemoryCandidate]] = [:]
    public init() {}
    public func append(project: String, _ candidate: MemoryCandidate) {
        history[project, default: []].append(candidate)
    }
    public func query(project: String, query: String) -> [MemoryCandidate] {
        history[project] ?? []
    }
}
