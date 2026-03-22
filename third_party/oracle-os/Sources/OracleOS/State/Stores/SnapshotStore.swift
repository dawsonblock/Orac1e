import Foundation
/// Persists snapshots for replay and recovery.
/// Note: Full disk persistence requires a Codable-compatible state representation.
public actor SnapshotStore {
    private let directory: URL
    private var store: [UUID: StateSnapshot] = [:]
    public init(directory: URL) { self.directory = directory }
    public func persist(_ snapshot: StateSnapshot) throws {
        store[snapshot.id] = snapshot
    }
    public func load(id: UUID) throws -> StateSnapshot {
        guard let snapshot = store[id] else {
            throw CocoaError(.fileNoSuchFile)
        }
        return snapshot
    }
}
