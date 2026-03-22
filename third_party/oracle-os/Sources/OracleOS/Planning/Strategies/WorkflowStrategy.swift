import Foundation
public struct WorkflowStrategy: Sendable {
    public init() {}
    public func score(intent: Intent, context: PlannerContext) -> Double {
        return 0.5
    }
}
