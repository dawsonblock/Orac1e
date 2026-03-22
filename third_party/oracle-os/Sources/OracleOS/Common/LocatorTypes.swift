import Foundation

public enum JSONPathHintComponent {
    public enum MatchType: String, Codable, Sendable {
        case exact
        case contains
        case prefix
    }
}

public struct Criterion: Codable, Sendable, Equatable {
    public var attribute: String
    public var value: String
    public var matchType: JSONPathHintComponent.MatchType?

    public init(
        attribute: String,
        value: String,
        matchType: JSONPathHintComponent.MatchType? = nil
    ) {
        self.attribute = attribute
        self.value = value
        self.matchType = matchType
    }
}

public struct Locator: Codable, Sendable, Equatable {
    public var criteria: [Criterion]
    public var computedNameContains: String?

    public init(
        criteria: [Criterion] = [],
        computedNameContains: String? = nil
    ) {
        self.criteria = criteria
        self.computedNameContains = computedNameContains
    }
}
