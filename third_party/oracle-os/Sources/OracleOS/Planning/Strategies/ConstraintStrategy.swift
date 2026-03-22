import Foundation
public struct ConstraintStrategy: Sendable {
    public init() {}
    public func isAllowed(intent: Intent, context: PlannerContext) -> Bool { true }
}
