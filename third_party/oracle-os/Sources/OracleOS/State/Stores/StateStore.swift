import Foundation
/// In-memory state store driven entirely by CommitCoordinator.
public actor StateStore {
    private var snapshots: [StateSnapshot] = []
    public init() {}
    public func save(_ snapshot: StateSnapshot) { snapshots.append(snapshot) }
    public func latest() -> StateSnapshot? { snapshots.last }
    public func all() -> [StateSnapshot] { snapshots }
}
