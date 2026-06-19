import Foundation

public final class SessionMemory {

    public var successfulSelectors: [String] = []
    public var failedSelectors: [String] = []
    public var recentActions: [ActionIntent] = []

    public init() {}

    public func recordSuccess(_ selector: String) {
        successfulSelectors.append(selector)
    }

    public func recordFailure(_ selector: String) {
        failedSelectors.append(selector)
    }

    public func recordAction(_ action: ActionIntent) {
        recentActions.append(action)
    }
}
