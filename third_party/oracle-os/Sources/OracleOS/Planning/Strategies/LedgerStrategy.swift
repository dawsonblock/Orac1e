import Foundation
public struct LedgerStrategy: Sendable {
    public init() {}
    public func score(intent: Intent, context: PlannerContext) -> Double { 0.5 }
}
