import Foundation
public struct ReasoningStrategy: Sendable {
    public init() {}
    public func score(intent: Intent, context: PlannerContext) -> Double { 0.8 }
}
