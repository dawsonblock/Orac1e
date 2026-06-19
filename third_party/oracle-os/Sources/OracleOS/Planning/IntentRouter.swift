import Foundation
/// Routes intents to the correct domain planner.
public struct IntentRouter {
    public init() {}
    public func route(_ intent: Intent) -> IntentDomain { intent.domain }
}
