public enum Postcondition: Codable, Sendable, Equatable {

    case elementFocused(String)
    case elementValueEquals(String, String)
    case elementAppeared(String)
    case elementDisappeared(String)
    case appFrontmost(String)
    case windowTitleContains(String)
    case urlContains(String)

    public enum Kind: String, Codable, Sendable {
        case elementFocused = "element_focused"
        case elementValueEquals = "element_value_equals"
        case elementAppeared = "element_appeared"
        case elementDisappeared = "element_disappeared"
        case appFrontmost = "app_frontmost"
        case windowTitleContains = "window_title_contains"
        case urlContains = "url_contains"
    }

    public var kind: Kind {
        switch self {
        case .elementFocused: return .elementFocused
        case .elementValueEquals: return .elementValueEquals
        case .elementAppeared: return .elementAppeared
        case .elementDisappeared: return .elementDisappeared
        case .appFrontmost: return .appFrontmost
        case .windowTitleContains: return .windowTitleContains
        case .urlContains: return .urlContains
        }
    }

    public var target: String {
        switch self {
        case .elementFocused(let id): return id
        case .elementValueEquals(let id, _): return id
        case .elementAppeared(let id): return id
        case .elementDisappeared(let id): return id
        case .appFrontmost(let app): return app
        case .windowTitleContains(let value): return value
        case .urlContains(let value): return value
        }
    }

    public var expected: String? {
        switch self {
        case .elementValueEquals(_, let value): return value
        case .windowTitleContains(let value): return value
        case .urlContains(let value): return value
        case .appFrontmost(let app): return app
        default: return nil
        }
    }
}
