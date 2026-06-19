import Foundation

public final class StateNode: @unchecked Sendable {
    public let id: PlanningStateID
    public var visitCount: Int

    public init(id: PlanningStateID, visitCount: Int = 0) {
        self.id = id
        self.visitCount = visitCount
    }
}
