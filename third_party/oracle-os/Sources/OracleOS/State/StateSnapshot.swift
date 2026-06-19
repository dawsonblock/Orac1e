import Foundation
/// Immutable snapshot of WorldStateModel after a commit.
public struct StateSnapshot: Sendable {
    public let id: UUID
    public let timestamp: Date
    public let sequenceNumber: Int
    public let state: WorldStateModel
    public let eventAncestry: [UUID]  // IDs of event envelopes that produced this snapshot

    public init(id: UUID = UUID(), timestamp: Date = Date(), sequenceNumber: Int,
                state: WorldStateModel, eventAncestry: [UUID]) {
        self.id = id; self.timestamp = timestamp; self.sequenceNumber = sequenceNumber
        self.state = state; self.eventAncestry = eventAncestry
    }
}
